//
//  LibraryBackupCommitter.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import GRDB
import Tagged

// the restore write chain: attach (never create outside DetailsComposer.write's
// own guard), seed chapters from the backup rather than a live fetch, write
// series-level state directly (not through DetailsComposer.Library.set(inLibrary:),
// which hardcodes addedDate = .now), write tracker links directly (not through
// Compositor.Trackers.link, which needs a live signed-in session), and dedupe
// collections by hand since nothing else in the codebase does.
// docs/features/library-backup.md §5 is the design this follows
struct LibraryBackupCommitter: MigrationCommitting {
    let database: DatabaseClient
    let registry: Compositor.Registry
    let refresher: Compositor.Refresh
    let log: AppLog

    init(
        database: DatabaseClient,
        registry: Compositor.Registry,
        refresher: Compositor.Refresh,
        log: AppLog = .shared
    ) {
        self.database = database
        self.registry = registry
        self.refresher = refresher
        self.log = log
    }

    func commit(_ entry: LibraryBackupEntry, candidate: MigrationCandidate) async -> MigrationOutcome {
        guard let source = registry.source(slug: candidate.sourceSlug) else {
            return .failed("That source is no longer installed.")
        }

        let seriesId: SeriesRecord.ID
        let originId: OriginRecord.ID

        do {
            let detail = try await source.details(seriesSlug: candidate.stub.slug)

            (seriesId, originId) = try await database.writer.write { db in
                guard let sourceId = try SourceRecord
                    .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                    .filter(SourceRecord.Columns.slug == candidate.sourceSlug)
                    .fetchOne(db)
                else { throw RecordError.missingIdentifier }

                // the same existence guard every commit chain in this
                // feature family uses - this exact source may already be
                // attached (a prior restore run, or added by hand)
                let known = try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter([detail.slug, candidate.stub.slug].contains(OriginRecord.Columns.slug))
                    .fetchOne(db)

                let ids: (SeriesRecord.ID, OriginRecord.ID)
                if let known, let originId = known.id {
                    ids = (known.seriesId, originId)
                } else {
                    ids = try DetailsComposer.write(
                        detail,
                        sourceId: sourceId,
                        matching: candidate.cover,
                        into: nil,
                        in: db
                    )
                }

                try Self.writeSeriesState(entry.seriesEntry, for: ids.0, in: db)
                return ids
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            log.log("backup import could not attach '\(candidate.title)' - \(error)", level: .error, category: "backup")
            return .failed(Failure(error, fallback: "Couldn't create this series").sentence)
        }

        // the series is real and in the library from here on - a failure
        // past this point is reported, not rolled back
        do {
            try await database.writer.write { db in
                try Self.seedChapters(entry.primaryOrigin?.chapters ?? [], for: originId, in: db)
                try Self.attachTags(entry.seriesEntry.tags, to: seriesId, in: db)
                try Self.attachAuthors(entry.seriesEntry.authors, to: seriesId, in: db)
                try Self.attachCollections(entry.seriesEntry.collections, to: seriesId, in: db)
                try Self.writeTrackerLinks(entry.seriesEntry.trackerLinks, to: seriesId, in: db)
                try Self.touchUpdatedDate(for: seriesId, in: db)
            }

            return .saved
        } catch is CancellationError {
            return .cancelled
        } catch {
            log.log("backup import could not finish '\(candidate.title)' - \(error)", level: .error, category: "backup")
            return .failed(Failure(error, fallback: "Series was created, but restoring its details failed").sentence)
        }
    }

    // MARK: - Series state

    // not DetailsComposer.Library.set(inLibrary:) - that hardcodes
    // addedDate = .now, which would tie every restored series for "just
    // added" and flood both LibrarySort.added and the Home "New Chapters"
    // feed (which gates on chapter.publishedDate > series.addedDate)
    private static func writeSeriesState(
        _ entry: LibraryBackup.SeriesEntry,
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws {
        _ = try SeriesRecord
            .filter(key: seriesId.rawValue)
            .updateAll(
                db,
                SeriesRecord.Columns.inLibrary.set(to: true),
                SeriesRecord.Columns.addedDate.set(to: Date(timeIntervalSince1970: TimeInterval(entry.addedDate))),
                SeriesRecord.Columns.lastReadDate.set(to: Date(timeIntervalSince1970: TimeInterval(entry.lastReadDate))),
                SeriesRecord.Columns.status.set(to: (Status(rawValue: entry.status) ?? .planning).rawValue),
                SeriesRecord.Columns.orientation.set(to: (Orientation(rawValue: entry.orientation) ?? .unknown).rawValue),
                SeriesRecord.Columns.showAllChapters.set(to: entry.showAllChapters),
                SeriesRecord.Columns.showHalfChapters.set(to: entry.showHalfChapters)
            )
    }

    // recomputed rather than carried in the payload (docs/features/library-backup.md
    // §3) - the same MAX(chapter.publishedDate) a live sync derives it from
    // (OriginRefresher.touchUpdatedDate), run once chapters actually exist
    private static func touchUpdatedDate(for seriesId: SeriesRecord.ID, in db: Database) throws {
        let latest = try Date.fetchOne(
            db,
            sql: """
                SELECT MAX(c.\(ChapterRecord.Columns.publishedDate.name))
                FROM \(ChapterRecord.databaseTableName) c
                JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
                WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
                """,
            arguments: [seriesId.rawValue]
        )
        guard let latest else { return }
        _ = try SeriesRecord
            .filter(key: seriesId.rawValue)
            .updateAll(db, SeriesRecord.Columns.updatedDate.set(to: latest))
    }

    // MARK: - Chapters

    // seeded straight from the backup, not fetched live - OriginRefresher.upsert's
    // shape (scanlator findOrCreate, one insert per entry), reused here
    // since the backup's ChapterEntry already carries what a live fetch
    // would produce. never overwrites a chapter that already exists locally
    // - a restore must not clobber progress a reader has made since
    private static func seedChapters(
        _ chapters: [LibraryBackup.SeriesEntry.ChapterEntry],
        for originId: OriginRecord.ID,
        in db: Database
    ) throws {
        guard !chapters.isEmpty else { return }

        let existing = try ChapterRecord
            .filter(ChapterRecord.Columns.originId == originId)
            .fetchAll(db)
        let existingSlugs = Set(existing.map(\.slug))

        var scanlators: [String: ScanlatorRecord.ID] = [:]
        for chapterEntry in chapters where scanlators[chapterEntry.scanlator] == nil {
            let scanlator = try ScanlatorRecord.findOrCreate(
                ScanlatorRecord(id: nil, name: chapterEntry.scanlator),
                in: db
            )
            if let scanlatorId = scanlator.id {
                scanlators[chapterEntry.scanlator] = scanlatorId
            }
        }

        for chapterEntry in chapters {
            guard !existingSlugs.contains(chapterEntry.slug),
                  let scanlatorId = scanlators[chapterEntry.scanlator],
                  let language = LanguageCode(rawValue: chapterEntry.language),
                  let url = URL(string: chapterEntry.url)
            else { continue }

            var chapter = ChapterRecord(
                id: nil,
                originId: originId,
                scanlatorId: scanlatorId,
                slug: chapterEntry.slug,
                title: chapterEntry.title,
                number: chapterEntry.number,
                publishedDate: Date(timeIntervalSince1970: TimeInterval(chapterEntry.publishedDate)),
                language: language,
                progress: chapterEntry.progress,
                lastReadDate: chapterEntry.hasLastReadDate
                    ? Date(timeIntervalSince1970: TimeInterval(chapterEntry.lastReadDate))
                    : nil,
                url: url,
                path: nil
            )
            try chapter.insert(db)
        }
    }

    // MARK: - Vocabulary

    private static func attachTags(_ names: [String], to seriesId: SeriesRecord.ID, in db: Database) throws {
        for name in names {
            _ = try TagRecord.attach(name, to: seriesId, in: db)
        }
    }

    private static func attachAuthors(_ names: [String], to seriesId: SeriesRecord.ID, in db: Database) throws {
        for name in names {
            let author = try AuthorRecord.findOrCreate(AuthorRecord(id: nil, name: name), in: db)
            guard let authorId = author.id else { continue }
            var join = SeriesAuthorRecord(seriesId: seriesId, authorId: authorId)
            try join.insert(db, onConflict: .ignore)
        }
    }

    // no findOrCreate exists for collections anywhere in the codebase
    // (CollectionRecord is not a UniqueRecord) - matched by hand,
    // case-insensitively, against every collection already fetched once
    // rather than a query per name
    private static func attachCollections(_ names: [String], to seriesId: SeriesRecord.ID, in db: Database) throws {
        guard !names.isEmpty else { return }

        var byLowercasedName = Dictionary(
            uniqueKeysWithValues: try CollectionRecord.fetchAll(db).compactMap { collection in
                collection.id.map { (collection.name.lowercased(), $0) }
            }
        )

        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let collectionId: CollectionRecord.ID
            if let existing = byLowercasedName[trimmed.lowercased()] {
                collectionId = existing
            } else {
                var collection = CollectionRecord(id: nil, name: trimmed)
                try collection.insert(db)
                guard let id = collection.id else { continue }
                collectionId = id
                byLowercasedName[trimmed.lowercased()] = id
            }

            var join = SeriesCollectionRecord(seriesId: seriesId, collectionId: collectionId)
            try join.insert(db, onConflict: .ignore)
        }
    }

    // MARK: - Tracker links

    // written directly, not through Compositor.Trackers.link(...) - that
    // call does a live round trip and requires a signed-in session.
    // "linked but not signed in" is already a first-class, fully-rendered
    // state elsewhere (docs/features/trackers.md), which is exactly what
    // this writes: the full snapshot a signed-out row already renders from,
    // reached directly instead of forcing a login first. upsert by the
    // (seriesId, tracker) unique key, so re-running an import updates
    // rather than throws
    private static func writeTrackerLinks(
        _ links: [LibraryBackup.SeriesEntry.TrackerLink],
        to seriesId: SeriesRecord.ID,
        in db: Database
    ) throws {
        for link in links {
            guard let tracker = Tracker(rawValue: link.tracker) else { continue }

            var record = SeriesTrackerRecord(
                seriesId: seriesId,
                tracker: tracker,
                remoteId: link.remoteID,
                remoteEntryId: link.hasRemoteEntryID ? link.remoteEntryID : nil,
                remoteTitle: link.remoteTitle,
                remoteStatus: link.hasRemoteStatus ? Status(rawValue: link.remoteStatus) : nil,
                remoteProgress: Int(link.remoteProgress),
                remoteScore: link.hasRemoteScore ? Int(link.remoteScore) : nil,
                totalChapters: link.hasTotalChapters ? Int(link.totalChapters) : nil
            )
            try record.insert(db, onConflict: .replace)
        }
    }
}

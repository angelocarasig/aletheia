//
//  LibraryBackupRestorer.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import GRDB
import Tagged

enum LibraryBackupRestorer {
    struct Summary: Equatable {
        var restoredCount = 0
        var disconnectedCount = 0
        var failures: [Failure] = []

        struct Failure: Equatable {
            let title: String
            let reason: String
        }
    }

    static func restore(
        _ backup: LibraryBackup,
        database: DatabaseClient,
        registry: Compositor.Registry,
        persistence: Compositor.Persistence,
        log: AppLog = .shared
    ) async -> Summary {
        var summary = Summary()

        do {
            try await persistence.wipe()
        } catch {
            log.log("backup restore couldn't wipe the database - \(error)", level: .error,
                category: "backup")
            return summary
        }

        let collectionSettingsByName = Dictionary(
            uniqueKeysWithValues: backup.collectionSettings.map {
                ($0.name.lowercased(), $0)
            }
        )

        for entry in backup.series {
            guard let primary = entry.origins.min(by: { $0.priority < $1.priority }) else {
                continue
            }

            if let source = registry.source(slug: primary.sourceSlug) {
                await attach(
                    entry, primary, source: source, collectionSettings: collectionSettingsByName,
                    database: database, summary: &summary, log: log)
            } else {
                await attachDisconnected(
                    entry, primary, collectionSettings: collectionSettingsByName,
                    database: database, summary: &summary, log: log)
            }
        }

        return summary
    }

    // MARK: - Source still installed

    private static func attach(
        _ entry: LibraryBackup.SeriesEntry,
        _ primary: LibraryBackup.SeriesEntry.OriginEntry,
        source: Source,
        collectionSettings: [String: LibraryBackup.CollectionSettings],
        database: DatabaseClient,
        summary: inout Summary,
        log: AppLog
    ) async {
        do {
            let detail = try await source.details(seriesSlug: primary.seriesSlug)

            let (seriesId, originId) = try await database.writer.write {
                db -> (SeriesRecord.ID, OriginRecord.ID) in
                guard
                    let sourceId =
                        try SourceRecord
                        .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                        .filter(SourceRecord.Columns.slug == primary.sourceSlug)
                        .fetchOne(db)
                else { throw RecordError.missingIdentifier }

                let known =
                    try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter([detail.slug, primary.seriesSlug].contains(OriginRecord.Columns.slug))
                    .fetchOne(db)

                let ids: (SeriesRecord.ID, OriginRecord.ID)
                if let known, let originId = known.id {
                    ids = (known.seriesId, originId)
                } else {
                    ids = try DetailsComposer.write(
                        detail, sourceId: sourceId, matching: nil, into: nil, in: db)
                }

                try writeSeriesState(entry, for: ids.0, in: db)
                return ids
            }

            try await database.writer.write { db in
                try seedChapters(primary.chapters, for: originId, in: db)
                try attachTags(entry.tags, to: seriesId, in: db)
                try attachAuthors(entry.authors, to: seriesId, in: db)
                try attachCollections(
                    entry.collections, settings: collectionSettings, to: seriesId, in: db)
                try writeTrackerLinks(entry.trackerLinks, to: seriesId, in: db)
                try touchUpdatedDate(for: seriesId, in: db)
            }

            summary.restoredCount += 1
        } catch {
            log.log(
                "backup restore failed for '\(entry.preferredTitle)' - \(error)", level: .error,
                category: "backup")
            summary.failures.append(
                Summary.Failure(
                    title: entry.preferredTitle,
                    reason: Failure(error, fallback: "Couldn't restore this series").sentence))
        }
    }

    // MARK: - Source not installed

    private static func attachDisconnected(
        _ entry: LibraryBackup.SeriesEntry,
        _ primary: LibraryBackup.SeriesEntry.OriginEntry,
        collectionSettings: [String: LibraryBackup.CollectionSettings],
        database: DatabaseClient,
        summary: inout Summary,
        log: AppLog
    ) async {
        do {
            try await database.writer.write { db in
                let known =
                    try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == nil)
                    .filter(OriginRecord.Columns.slug == primary.seriesSlug)
                    .fetchOne(db)

                let seriesId: SeriesRecord.ID
                let originId: OriginRecord.ID

                if let known, let knownOriginId = known.id {
                    (seriesId, originId) = (known.seriesId, knownOriginId)
                } else {
                    var series = SeriesRecord()
                    try series.insert(db)
                    guard let newSeriesId = series.id else { throw RecordError.missingIdentifier }
                    try SeriesLanguagePriorityRecord.seedDefaults(for: newSeriesId, in: db)

                    var origin = OriginRecord(
                        seriesId: newSeriesId,
                        sourceId: nil,
                        slug: primary.seriesSlug,
                        url: "",
                        priority: 0
                    )
                    try origin.insert(db)
                    guard let newOriginId = origin.id else { throw RecordError.missingIdentifier }

                    let title = try TitleRecord.findOrCreate(
                        TitleRecord(
                            id: nil, seriesId: newSeriesId, metadataId: nil,
                            value: entry.preferredTitle),
                        in: db
                    )
                    _ =
                        try SeriesRecord
                        .filter(key: newSeriesId.rawValue)
                        .updateAll(
                            db, SeriesRecord.Columns.preferredTitleId.set(to: title.id?.rawValue))

                    (seriesId, originId) = (newSeriesId, newOriginId)
                }

                try writeSeriesState(entry, for: seriesId, in: db)
                try seedChapters(primary.chapters, for: originId, in: db)
                try attachTags(entry.tags, to: seriesId, in: db)
                try attachAuthors(entry.authors, to: seriesId, in: db)
                try attachCollections(
                    entry.collections, settings: collectionSettings, to: seriesId, in: db)
                try writeTrackerLinks(entry.trackerLinks, to: seriesId, in: db)
                try touchUpdatedDate(for: seriesId, in: db)
            }

            summary.disconnectedCount += 1
        } catch {
            log.log(
                "backup restore (disconnected) failed for '\(entry.preferredTitle)' - \(error)",
                level: .error, category: "backup")
            summary.failures.append(
                Summary.Failure(
                    title: entry.preferredTitle,
                    reason: Failure(error, fallback: "Couldn't restore this series").sentence))
        }
    }

    // MARK: - Shared writes

    private static func writeSeriesState(
        _ entry: LibraryBackup.SeriesEntry,
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws {
        _ =
            try SeriesRecord
            .filter(key: seriesId.rawValue)
            .updateAll(
                db,
                SeriesRecord.Columns.inLibrary.set(to: true),
                SeriesRecord.Columns.addedDate.set(
                    to: Date(timeIntervalSince1970: TimeInterval(entry.addedDate))),
                SeriesRecord.Columns.lastReadDate.set(
                    to: Date(timeIntervalSince1970: TimeInterval(entry.lastReadDate))),
                SeriesRecord.Columns.status.set(
                    to: (Status(rawValue: entry.status) ?? .planning).rawValue),
                SeriesRecord.Columns.orientation.set(
                    to: (Orientation(rawValue: entry.orientation) ?? .unknown).rawValue),
                SeriesRecord.Columns.showAllChapters.set(to: entry.showAllChapters),
                SeriesRecord.Columns.showHalfChapters.set(to: entry.showHalfChapters)
            )
    }

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
        _ =
            try SeriesRecord
            .filter(key: seriesId.rawValue)
            .updateAll(db, SeriesRecord.Columns.updatedDate.set(to: latest))
    }

    private static func seedChapters(
        _ chapters: [LibraryBackup.SeriesEntry.ChapterEntry],
        for originId: OriginRecord.ID,
        in db: Database
    ) throws {
        guard !chapters.isEmpty else { return }

        let existing =
            try ChapterRecord
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
                publishedDate: Date(
                    timeIntervalSince1970: TimeInterval(chapterEntry.publishedDate)),
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

    private static func attachTags(_ names: [String], to seriesId: SeriesRecord.ID, in db: Database)
        throws
    {
        for name in names {
            _ = try TagRecord.attach(name, to: seriesId, in: db)
        }
    }

    private static func attachAuthors(
        _ names: [String], to seriesId: SeriesRecord.ID, in db: Database
    ) throws {
        for name in names {
            let author = try AuthorRecord.findOrCreate(AuthorRecord(id: nil, name: name), in: db)
            guard let authorId = author.id else { continue }
            var join = SeriesAuthorRecord(seriesId: seriesId, authorId: authorId)
            try join.insert(db, onConflict: .ignore)
        }
    }

    private static func attachCollections(
        _ names: [String], settings: [String: LibraryBackup.CollectionSettings],
        to seriesId: SeriesRecord.ID, in db: Database
    ) throws {
        guard !names.isEmpty else { return }

        var byLowercasedName = Dictionary(
            uniqueKeysWithValues: try CollectionRecord.fetchAll(db).compactMap { collection in
                collection.id.map { (collection.name.lowercased(), $0) }
            }
        )

        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // a reserved name reaching here means the backup predates this
            // constraint or was hand-edited - dropped rather than inserted,
            // since the db CHECK would reject the insert anyway
            guard !trimmed.isEmpty, !CollectionRecord.isReserved(trimmed) else { continue }

            let collectionId: CollectionRecord.ID
            if let existing = byLowercasedName[trimmed.lowercased()] {
                collectionId = existing
            } else {
                // absent from an older backup's settings list decodes to a
                // default CollectionSettings() - both flags false, same as
                // this collection had never carried any
                let matched = settings[trimmed.lowercased()]
                var collection = CollectionRecord(id: nil, name: trimmed)
                collection.hideFromHome = matched?.hideFromHome ?? false
                collection.requiresFaceId = matched?.requiresFaceID ?? false
                try collection.insert(db)
                guard let id = collection.id else { continue }
                collectionId = id
                byLowercasedName[trimmed.lowercased()] = id
            }

            var join = SeriesCollectionRecord(seriesId: seriesId, collectionId: collectionId)
            try join.insert(db, onConflict: .ignore)
        }
    }

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

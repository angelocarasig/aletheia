//
//  DetailsComposer+Observation.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Tagged

extension DetailsComposer {
    struct Stored: Sendable {
        let series: SeriesRecord
        let entry: RichfulEntryView
        let chapters: [Chapters.Row]
        let origins: [Origin]
        let covers: [Cover]
        let titles: [Title]
        let collections: [Collection]
        let trackers: [SeriesTrackerRecord]
        let furthest: Int
    }
}

extension DetailsComposer.Stored {
    struct Origin: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let slug: String
        let url: String
        let priority: Int
        let chapterCount: Int
        let chaptersFetchedDate: Date
        let metadataFetchedDate: Date
        let fetchAttemptedDate: Date
        let fetchError: String?
        let synopsis: String
        let classification: Classification
        let publication: Publication
        let isSynopsis: Bool
        let isMetadata: Bool
        let sourceSlug: String?
        let sourceName: String?
        let sourceBaseURL: URL?
        let sourceReferer: URL?
        let disconnected: Bool
        let disabled: Bool
        let installed: Bool
    }

    struct Collection: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let name: String
        let count: Int
        let contains: Bool
    }

    struct Title: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let value: String
        let sourceSlug: String?
        let sourceName: String?
        let isPreferred: Bool
    }

    struct Cover: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let url: URL
        let path: String?
        let sourceSlug: String?
        let sourceName: String?
        let isPreferred: Bool
    }
}

extension DetailsComposer {
    // watcher for the whole screen... cancels whatever it replaces, so
    // resolving to a different row after disambiguation leaves nothing behind
    // reading the old one
    func observe(_ id: SeriesRecord.ID) {
        seriesId = id
        failure = nil
        stream?.cancel()

        // weak, so the screen going away releases the composer rather than the
        // observation holding it open. the loop then ends on its next emission
        stream = Task { [weak self, database, registry] in
            let observation = ValueObservation.tracking { db -> Stored? in
                guard
                    let series = try SeriesRecord.fetchOne(db, key: id.rawValue),
                    let entry = try RichfulEntryView
                        .filter(RichfulEntryView.Columns.seriesId == id.rawValue)
                        .fetchOne(db)
                else { return nil }

                return Stored(
                    series: series,
                    entry: entry,
                    // mapped here rather than on the other side: this closure
                    // runs on the dbpool, and a series with four
                    // hundred chapters was rebuilding every row on the main
                    // actor on every emission - measured at ~700ms after a
                    // bulk insert
                    chapters: Chapters.display(try Chapters.rows(for: id, in: db), registry: registry),
                    origins: try Self.origins(for: id, in: db),
                    covers: try Self.covers(for: id, in: db),
                    titles: try Self.titles(for: id, in: db),
                    collections: try Self.collections(for: id, in: db),
                    trackers: try SeriesTrackerRecord
                        .filter(SeriesTrackerRecord.Columns.seriesId == id.rawValue)
                        .fetchAll(db),
                    furthest: try SeriesTrackerRecord.furthest(for: id, in: db)
                )
            }

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    guard let stored else { continue }

                    self.apply(stored)
                }
            } catch {
                // a background load. the screen keeps what it has rather than nagging about it
                AppLog.shared.log("observation failed - \(error)", level: .error, category: "details")
            }
        }
    }

    // fan-out... fills in what the root itself draws, hands every child its
    // own slice, and marks the first bundle as arrived so the skeleton can go.
    //
    // not the DetailsApplying conformance - this is the caller of it. every
    // child implements that protocol, and this is where they are called from
    func apply(_ stored: Stored) {
        series.apply(stored)
        library.apply(stored)
        chapters.apply(stored)
        sources.apply(stored)
        tracking.apply(stored)
        refresh.apply(stored)

        if !applied { applied = true }

        refresh.adopt()
        refresh.prime()
    }

    // which series this screen is for. runs entirely against the database and
    // entirely before the network: a slug hit on this source, then a title hit
    // in the library, so a series you already own under another source is
    // never missed and never duplicated
    func resolve() async {
        guard let opener, let stub else {
            failure = Failure(
                title: "Source Unavailable",
                message: "No installed source can open this series.",
                isRetryable: false
            )
            return
        }

        let match = try? await database.reader.read { db in
            try SeriesRecord.match(stub, from: opener.descriptor.slug, in: db)
        }

        held = match?.existing

        switch match?.outcome {
        case .inLibrary(let id):
            observe(id)

        case .candidates(let ids):
            // failing to build the prompt is the same answer as finding no
            // candidates - carry on rather than stranding the screen
            if await !identity.load(ids) { await settle() }

        case .unmatched, nil:
            await settle()
        }
    }

    // where the flow lands when nothing in the library claims it - reuse the
    // row we already have, or write a new one
    func settle() async {
        if let held {
            observe(held)
        } else {
            await store(into: nil)
        }
    }

    // opening a search result writes the whole row set with inLibrary = 0, so
    // it reads offline and a second visit refetches nothing. passing an
    // existing id writes into that row instead of minting one
    func store(into existing: SeriesRecord.ID?) async {
        guard let opener, let stub else {
            // a library entry always carries its row id, so it never arrives here
            failure = Failure(
                title: "Source Unavailable",
                message: "No installed source can open this series.",
                isRetryable: false
            )
            return
        }

        do {
            let detail = try await opener.details(seriesSlug: stub.slug)
            let sourceSlug = opener.descriptor.slug
            let stubCover = stub.cover

            let ids = try await database.writer.write { db -> (SeriesRecord.ID, OriginRecord.ID) in
                guard let sourceId = try SourceRecord
                    .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                    .filter(SourceRecord.Columns.slug == sourceSlug)
                    .fetchOne(db)
                else { throw RecordError.missingIdentifier }

                // the details response carries the canonical slug, and the stub
                // may have been opened under an older one - both have to be
                // checked or a series already stored is created a second time
                let known = try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter([detail.slug, stub.slug].contains(OriginRecord.Columns.slug))
                    .fetchOne(db)

                if let known, let originId = known.id {
                    return (known.seriesId, originId)
                }

                return try Self.write(
                    detail,
                    sourceId: sourceId,
                    matching: stubCover,
                    into: existing,
                    in: db
                )
            }

            observe(ids.0)
            assets.enqueue(series: ids.0)

            // attaching to an existing series happens behind a screen already
            // showing chapters from other origins, so the fetch gets the
            // refresh pill - badged with the new source's icon - rather than
            // passing silently. a fresh open keeps the skeleton as its indicator
            if existing != nil {
                let origin = Refresh.Origin(
                    id: ids.1.rawValue,
                    slug: stub.slug,
                    sourceSlug: sourceSlug,
                    name: opener.descriptor.name,
                    icon: opener.descriptor.icon
                )

                refresh.began(origin)
                let result = await refresher.chapters(
                    source: opener,
                    seriesSlug: stub.slug,
                    originId: ids.1
                )
                refresh.ended(origin, result)
            } else {
                _ = await refresher.chapters(source: opener, seriesSlug: stub.slug, originId: ids.1)
            }
        } catch {
            failure = Failure(error, fallback: "Couldn't Load Series")
        }
    }
}

extension DetailsComposer {
    nonisolated static func origins(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [Stored.Origin] {
        let sql = """
            SELECT
                o.id AS id,
                o.\(OriginRecord.Columns.slug.name) AS slug,
                o.\(OriginRecord.Columns.url.name) AS url,
                o.\(OriginRecord.Columns.priority.name) AS priority,
                o.\(OriginRecord.Columns.chaptersFetchedDate.name) AS chaptersFetchedDate,
                o.\(OriginRecord.Columns.metadataFetchedDate.name) AS metadataFetchedDate,
                o.\(OriginRecord.Columns.fetchAttemptedDate.name) AS fetchAttemptedDate,
                o.\(OriginRecord.Columns.fetchError.name) AS fetchError,
                o.\(OriginRecord.Columns.synopsis.name) AS synopsis,
                o.\(OriginRecord.Columns.classification.name) AS classification,
                o.\(OriginRecord.Columns.publication.name) AS publication,
                COALESCE(o.id = s.\(SeriesRecord.Columns.preferredSynopsisOriginId.name), 0) AS isSynopsis,
                COALESCE(o.id = s.\(SeriesRecord.Columns.preferredMetadataOriginId.name), 0) AS isMetadata,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                src.\(SourceRecord.Columns.baseURL.name) AS sourceBaseURL,
                src.\(SourceRecord.Columns.referer.name) AS sourceReferer,
                (o.\(OriginRecord.Columns.sourceId.name) IS NULL) AS disconnected,
                COALESCE(src.\(SourceRecord.Columns.disabled.name), 0) AS disabled,
                COALESCE(src.\(SourceRecord.Columns.installed.name), 0) AS installed,
                (
                    SELECT COUNT(*)
                    FROM \(ChapterRecord.databaseTableName) c
                    WHERE c.\(ChapterRecord.Columns.originId.name) = o.id
                ) AS chapterCount
            FROM \(OriginRecord.databaseTableName) o
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.seriesId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            ORDER BY
                (o.\(OriginRecord.Columns.sourceId.name) IS NULL OR COALESCE(src.\(SourceRecord.Columns.disabled.name), 0)) ASC,
                o.\(OriginRecord.Columns.priority.name) ASC,
                o.id ASC
            """

        return try Stored.Origin.fetchAll(db, sql: sql, arguments: [id])
    }

    // every collection, not just this series' - the picker lists all of them,
    // so a row has to know both its size and whether this series is in it
    nonisolated static func collections(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [Stored.Collection] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(CollectionRecord.Columns.name.name) AS name,
                (SELECT COUNT(*)
                   FROM \(SeriesCollectionRecord.databaseTableName) sc
                  WHERE sc.\(SeriesCollectionRecord.Columns.collectionId.name) = c.id) AS count,
                EXISTS(SELECT 1
                         FROM \(SeriesCollectionRecord.databaseTableName) sc
                        WHERE sc.\(SeriesCollectionRecord.Columns.collectionId.name) = c.id
                          AND sc.\(SeriesCollectionRecord.Columns.seriesId.name) = ?) AS contains
            FROM \(CollectionRecord.databaseTableName) c
            ORDER BY c.\(CollectionRecord.Columns.name.name) ASC
            """

        return try Stored.Collection.fetchAll(db, sql: sql, arguments: [id])
    }

    nonisolated static func titles(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [Stored.Title] {
        let sql = """
            SELECT
                t.id AS id,
                t.\(TitleRecord.Columns.value.name) AS value,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                COALESCE(t.id = s.\(SeriesRecord.Columns.preferredTitleId.name), 0) AS isPreferred
            FROM \(TitleRecord.databaseTableName) t
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = t.\(TitleRecord.Columns.seriesId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = t.\(TitleRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE t.\(TitleRecord.Columns.seriesId.name) = ?
            ORDER BY t.id ASC
            """

        return try Stored.Title.fetchAll(db, sql: sql, arguments: [id])
    }

    nonisolated static func covers(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [Stored.Cover] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(CoverRecord.Columns.url.name) AS url,
                c.\(CoverRecord.Columns.path.name) AS path,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                COALESCE(c.id = s.\(SeriesRecord.Columns.preferredCoverId.name), 0) AS isPreferred
            FROM \(CoverRecord.databaseTableName) c
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = c.\(CoverRecord.Columns.seriesId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(CoverRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE c.\(CoverRecord.Columns.seriesId.name) = ?
            ORDER BY c.id ASC
            """

        return try Stored.Cover.fetchAll(db, sql: sql, arguments: [id])
    }

    // the whole row set for a series this source has just described. an
    // existing id attaches a new origin to a series already on screen instead
    // of minting one
    nonisolated static func write(
        _ detail: SeriesDetail,
        sourceId: SourceRecord.ID,
        matching stubCover: URL?,
        into existing: SeriesRecord.ID?,
        in db: Database
    ) throws -> (SeriesRecord.ID, OriginRecord.ID) {
        var series = SeriesRecord()
        let seriesId: SeriesRecord.ID

        if let existing {
            seriesId = existing
        } else {
            try series.insert(db)
            guard let inserted = series.id else { throw RecordError.missingIdentifier }
            seriesId = inserted
        }

        try SeriesLanguagePriorityRecord.seedDefaults(for: seriesId, in: db)

        let priority = try Int.fetchOne(
            db,
            sql: """
                SELECT COALESCE(MAX(\(OriginRecord.Columns.priority.name)), -1) + 1
                FROM \(OriginRecord.databaseTableName)
                WHERE \(OriginRecord.Columns.seriesId.name) = ?
                """,
            arguments: [seriesId]
        ) ?? 0

        var origin = OriginRecord(
            id: nil,
            seriesId: seriesId,
            sourceId: sourceId,
            slug: detail.slug,
            url: detail.url.absoluteString,
            synopsis: detail.synopsis,
            priority: priority,
            classification: detail.classification,
            publication: detail.publication,
            
            // this origin exists because a details response just arrived
            metadataFetchedDate: .now
        )
        try origin.insert(db)
        guard let originId = origin.id else { throw RecordError.missingIdentifier }

        // the source's own title goes in first, and becomes the preferred one
        var preferredTitleId: TitleRecord.ID?
        for value in [detail.title] + detail.altTitles {
            let title = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: seriesId, originId: originId, value: value),
                in: db
            )
            if preferredTitleId == nil { preferredTitleId = title.id }
        }

        // the search result's own cover joins the pool, LAST. it used to be
        // passed in for matching and then discarded, which meant the one url in
        // this whole transaction known to work - it had just rendered on the
        // card the reader tapped - was the only one not kept. a series whose
        // details response gave a dead url therefore had a pool of exactly one
        // dead url, nothing to fall back to, and no way to ever recover.
        //
        // last rather than first, so a source whose details artwork is better
        // than its search thumbnail still wins on quality: the preference is
        // still chosen from detail.covers, and this is the rung underneath.
        //
        // it also makes cover()'s first tier reachable for the first time -
        // that tier matches against the stub url, in a set that until now could
        // never contain it
        let pool = detail.covers + (stubCover.map { detail.covers.contains($0) ? [] : [$0] } ?? [])

        let primary = cover(among: detail.covers, matching: stubCover) ?? stubCover
        var preferredCoverId: CoverRecord.ID?
        for url in pool {
            let cover = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: seriesId, originId: originId, url: url, path: nil),
                in: db
            )
            if url == primary { preferredCoverId = cover.id }
        }

        for name in detail.authors {
            let author = try AuthorRecord.findOrCreate(AuthorRecord(id: nil, name: name), in: db)
            guard let authorId = author.id else { continue }
            var link = SeriesAuthorRecord(id: nil, seriesId: seriesId, authorId: authorId)
            try link.insert(db, onConflict: .ignore)
        }

        for name in detail.tags {
            let tag = try TagRecord.findOrCreate(
                TagRecord(id: nil, normalizedName: sanitised(name), displayName: name, canonicalId: nil),
                in: db
            )
            guard let tagId = tag.id else { continue }
            var link = SeriesTagRecord(id: nil, seriesId: seriesId, tagId: tagId)
            try link.insert(db, onConflict: .ignore)
        }

        // an attached origin joins a series that already has its preferences
        // set, and taking them over would swap the display out from under the
        // reader
        guard existing == nil else { return (seriesId, originId) }

        series.preferredTitleId = preferredTitleId
        series.preferredCoverId = preferredCoverId
        series.preferredSynopsisOriginId = originId
        series.preferredMetadataOriginId = originId
        try series.update(db)

        return (seriesId, originId)
    }

    // exact url, else the same filename ignoring extension, else the first
    // listed
    nonisolated static func cover(
        among covers: [URL],
        matching stub: URL?
    ) -> URL? {
        guard let stub else { return covers.first }
        if let exact = covers.first(where: { $0 == stub }) { return exact }

        let stem = stub.deletingPathExtension().lastPathComponent
        return covers.first { $0.deletingPathExtension().lastPathComponent == stem } ?? covers.first
    }

    nonisolated static func sanitised(_ tag: String) -> String {
        tag.lowercased().replacingOccurrences(of: " ", with: "")
    }
}

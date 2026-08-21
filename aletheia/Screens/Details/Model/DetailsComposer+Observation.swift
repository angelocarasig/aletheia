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
        let suppliers: [Supplier]
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
        // just a timestamp mirror - the metadata row's own content lives on
        // Stored.Supplier, this is nil once that row is gone
        let metadataFetchedDate: Date?
        let fetchAttemptedDate: Date
        let fetchError: String?
        let sourceSlug: String?
        let sourceName: String?
        let sourceBaseURL: URL?
        let sourceReferer: URL?
        let disconnected: Bool
        let disabled: Bool
        let installed: Bool
    }

    // queries MetadataRecord directly rather than deriving from origins - a
    // linked tracker owns a metadata row with no origin at all, so deriving
    // from origins would make every tracker invisible to these pickers
    struct Supplier: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let synopsis: String
        let classification: Classification
        let publication: Publication
        let isSynopsis: Bool
        let isClassification: Bool
        let isPublication: Bool
        let sourceSlug: String?
        let sourceName: String?
        let tracker: Tracker?
        let detached: Bool
    }

    struct Collection: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let name: String
        let count: Int
        let contains: Bool
    }

    // both the origin and tracker paths must be walked to resolve provenance,
    // or a tracker's contribution renders unlabelled - indistinguishable from
    // a dead source
    struct Title: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let value: String
        let sourceSlug: String?
        let sourceName: String?
        let tracker: Tracker?
        let isPreferred: Bool
    }

    struct Cover: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let url: URL
        let path: String?
        let sourceSlug: String?
        let sourceName: String?
        let tracker: Tracker?
        let isPreferred: Bool
    }
}

extension DetailsComposer {
    func observe(_ id: SeriesRecord.ID) {
        seriesId = id
        failure = nil
        stream?.cancel()

        // weak, so the screen going away releases the composer rather than the
        // observation holding it open - the loop ends on its next emission
        stream = Task { [weak self, database, registry] in
            let observation = ValueObservation.tracking { db -> Stored? in
                guard
                    let series = try SeriesRecord.fetchOne(db, key: id.rawValue),
                    let entry =
                        try RichfulEntryView
                        .filter(RichfulEntryView.Columns.seriesId == id.rawValue)
                        .fetchOne(db)
                else { return nil }

                return Stored(
                    series: series,
                    entry: entry,
                    // mapped inside this dbpool closure, not in apply() on the
                    // main actor - measured ~700ms for 400 chapters otherwise
                    chapters: Chapters.display(
                        try Chapters.rows(for: id, in: db), registry: registry),
                    origins: try Self.origins(for: id, in: db),
                    suppliers: try Self.suppliers(for: id, in: db),
                    covers: try Self.covers(for: id, in: db),
                    titles: try Self.titles(for: id, in: db),
                    collections: try Self.collections(for: id, in: db),
                    trackers:
                        try SeriesTrackerRecord
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
                // keeps what it has rather than surfacing a failure for a
                // background load
                AppLog.shared.log(
                    "observation failed - \(error)", level: .error, category: "details")
            }
        }
    }

    func apply(_ stored: Stored) {
        series.apply(stored)
        library.apply(stored)
        chapters.apply(stored)
        sources.apply(stored)
        tracking.apply(stored)
        refresh.apply(stored)
        recommendations.apply(stored)
        cadence.apply(stored)

        if !applied { applied = true }

        refresh.adopt()
        refresh.prime()
    }

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
            if await !identity.load(ids) { await settle() }

        case .unmatched, nil:
            await settle()
        }
    }

    func settle() async {
        guard let opener, let stub else {
            failure = Failure(
                title: "Source Unavailable",
                message: "No installed source can open this series.",
                isRetryable: false
            )
            return
        }

        if let held {
            observe(held)
        } else {
            await store(into: nil, opener: opener, stub: stub)
        }
    }

    // opener/stub are explicit, not self.opener/self.stub - resetSeries()
    // calls this for an already-in-library series (entry is .library, so
    // those computed properties are nil), reusing the same write path a
    // fresh-from-search add already takes
    func store(into existing: SeriesRecord.ID?, opener: Source, stub: SeriesStub) async {
        do {
            let detail = try await opener.details(seriesSlug: stub.slug)
            let sourceSlug = opener.descriptor.slug
            let stubCover = stub.cover

            let ids = try await database.writer.write { db -> (SeriesRecord.ID, OriginRecord.ID) in
                guard
                    let sourceId =
                        try SourceRecord
                        .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                        .filter(SourceRecord.Columns.slug == sourceSlug)
                        .fetchOne(db)
                else { throw RecordError.missingIdentifier }

                // both the canonical slug (from the details response) and the
                // stub's must be checked, or an older-slug reopen creates a
                // duplicate series
                let known =
                    try OriginRecord
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

    // troubleshooting, not an everyday action: deletes this series' row -
    // cascading reading history, progress, downloads, and cached
    // recommendations away with it - then re-adds it fresh from its primary
    // source, the same write path a from-search add already takes. entry is
    // .library here, so self.opener/self.stub are nil (source-only) -
    // rebuilt from the series' own current data instead. any source beyond
    // the primary is not recreated; the confirmation alert says so
    func resetSeries() async {
        guard let id = seriesId else { return }
        guard let origin = sources.origins.first, let sourceSlug = origin.sourceSlug,
            let opener = registry.source(slug: sourceSlug)
        else {
            failure = Failure(
                title: "Source Unavailable",
                message: "No installed source can open this series.",
                isRetryable: false
            )
            return
        }
        let stub = SeriesStub(slug: origin.slug, title: series.title, cover: series.cover)

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord.deleteOne(db, key: id.rawValue)
            }
        } catch {
            failure = Failure(error, fallback: "Couldn't Reset Series")
            return
        }

        seriesId = nil
        held = nil
        await store(into: nil, opener: opener, stub: stub)
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
                md.\(MetadataRecord.Columns.fetchedDate.name) AS metadataFetchedDate,
                o.\(OriginRecord.Columns.fetchAttemptedDate.name) AS fetchAttemptedDate,
                o.\(OriginRecord.Columns.fetchError.name) AS fetchError,
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
            LEFT JOIN \(MetadataRecord.databaseTableName) md ON md.\(MetadataRecord.Columns.originId.name) = o.id
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            ORDER BY
                (o.\(OriginRecord.Columns.sourceId.name) IS NULL OR COALESCE(src.\(SourceRecord.Columns.disabled.name), 0)) ASC,
                o.\(OriginRecord.Columns.priority.name) ASC,
                o.id ASC
            """

        return try Stored.Origin.fetchAll(db, sql: sql, arguments: [id])
    }

    nonisolated static func suppliers(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [Stored.Supplier] {
        let sql = """
            SELECT
                md.id AS id,
                md.\(MetadataRecord.Columns.synopsis.name) AS synopsis,
                md.\(MetadataRecord.Columns.classification.name) AS classification,
                md.\(MetadataRecord.Columns.publication.name) AS publication,
                COALESCE(md.id = s.\(SeriesRecord.Columns.preferredSynopsisId.name), 0) AS isSynopsis,
                COALESCE(md.id = s.\(SeriesRecord.Columns.preferredClassificationId.name), 0) AS isClassification,
                COALESCE(md.id = s.\(SeriesRecord.Columns.preferredPublicationId.name), 0) AS isPublication,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                st.\(SeriesTrackerRecord.Columns.tracker.name) AS tracker,
                (md.\(MetadataRecord.Columns.originId.name) IS NULL
                 AND md.\(MetadataRecord.Columns.trackerId.name) IS NULL) AS detached
            FROM \(MetadataRecord.databaseTableName) md
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = md.\(MetadataRecord.Columns.seriesId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = md.\(MetadataRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            LEFT JOIN \(SeriesTrackerRecord.databaseTableName) st ON st.id = md.\(MetadataRecord.Columns.trackerId.name)
            WHERE md.\(MetadataRecord.Columns.seriesId.name) = ?
            ORDER BY
                (md.\(MetadataRecord.Columns.originId.name) IS NULL) ASC,
                o.\(OriginRecord.Columns.priority.name) ASC,
                md.id ASC
            """

        return try Stored.Supplier.fetchAll(db, sql: sql, arguments: [id])
    }

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
                st.\(SeriesTrackerRecord.Columns.tracker.name) AS tracker,
                COALESCE(t.id = s.\(SeriesRecord.Columns.preferredTitleId.name), 0) AS isPreferred
            FROM \(TitleRecord.databaseTableName) t
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = t.\(TitleRecord.Columns.seriesId.name)
            LEFT JOIN \(MetadataRecord.databaseTableName) md ON md.id = t.\(TitleRecord.Columns.metadataId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = md.\(MetadataRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            LEFT JOIN \(SeriesTrackerRecord.databaseTableName) st ON st.id = md.\(MetadataRecord.Columns.trackerId.name)
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
                st.\(SeriesTrackerRecord.Columns.tracker.name) AS tracker,
                COALESCE(c.id = s.\(SeriesRecord.Columns.preferredCoverId.name), 0) AS isPreferred
            FROM \(CoverRecord.databaseTableName) c
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = c.\(CoverRecord.Columns.seriesId.name)
            LEFT JOIN \(MetadataRecord.databaseTableName) md ON md.id = c.\(CoverRecord.Columns.metadataId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = md.\(MetadataRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            LEFT JOIN \(SeriesTrackerRecord.databaseTableName) st ON st.id = md.\(MetadataRecord.Columns.trackerId.name)
            WHERE c.\(CoverRecord.Columns.seriesId.name) = ?
            ORDER BY c.id ASC
            """

        return try Stored.Cover.fetchAll(db, sql: sql, arguments: [id])
    }

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

        let priority =
            try Int.fetchOne(
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
            priority: priority
        )
        try origin.insert(db)
        guard let originId = origin.id else { throw RecordError.missingIdentifier }

        let source = try SourceRecord.fetchOne(db, key: sourceId.rawValue)
        let supplier = MetadataRecord.supplier(
            source: source?.slug ?? "\(sourceId.rawValue)", origin: detail.slug)

        // adopt re-finds the orphaned row from a prior removal instead of colliding with it
        var metadata = try MetadataRecord.adopt(
            seriesId: seriesId, supplier: supplier, originId: originId, in: db)
        try metadata.updateChanges(db) {
            $0.synopsis = detail.synopsis
            $0.classification = detail.classification
            $0.publication = detail.publication
            $0.fetchedDate = .now
        }
        guard let metadataId = metadata.id else { throw RecordError.missingIdentifier }

        var preferredTitleId: TitleRecord.ID?
        for value in [detail.title] + detail.altTitles {
            let title = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: seriesId, metadataId: metadataId, value: value),
                in: db
            )
            if preferredTitleId == nil { preferredTitleId = title.id }
        }

        // stub cover joins the pool LAST, not first. it used to be used only for
        // matching then discarded, so a details response with a dead cover url
        // left a pool of exactly one dead url with nothing to fall back to.
        // last, not first, so a source whose details artwork beats its search
        // thumbnail still wins on quality - and it makes cover()'s first tier
        // (which matches against the stub url) reachable at all
        let pool = detail.covers + (stubCover.map { detail.covers.contains($0) ? [] : [$0] } ?? [])

        let primary = cover(among: detail.covers, matching: stubCover) ?? stubCover
        var preferredCoverId: CoverRecord.ID?
        for url in pool {
            let cover = try CoverRecord.findOrCreate(
                CoverRecord(
                    id: nil, seriesId: seriesId, metadataId: metadataId, url: url, path: nil),
                in: db
            )
            if url == primary { preferredCoverId = cover.id }
        }

        for name in detail.authors {
            try AuthorRecord.attach(name, to: seriesId, in: db)
        }

        for name in detail.tags {
            try TagRecord.attach(name, to: seriesId, in: db)
        }

        // an attached origin joins a series that already has its preferences
        // set, and taking them over would swap the display out from under the
        // reader
        guard existing == nil else { return (seriesId, originId) }

        series.preferredTitleId = preferredTitleId
        series.preferredCoverId = preferredCoverId
        series.preferredSynopsisId = metadataId
        series.preferredClassificationId = metadataId
        series.preferredPublicationId = metadataId
        try series.update(db)

        return (seriesId, originId)
    }

    nonisolated static func cover(
        among covers: [URL],
        matching stub: URL?
    ) -> URL? {
        guard let stub else { return covers.first }
        if let exact = covers.first(where: { $0 == stub }) { return exact }

        let stem = stub.deletingPathExtension().lastPathComponent
        return covers.first { $0.deletingPathExtension().lastPathComponent == stem } ?? covers.first
    }

}

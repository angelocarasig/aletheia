//
//  DetailsComposer+Identity.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Observation
import Tagged

extension DetailsComposer {
    @MainActor
    @Observable
    final class Identity: DetailsWriting {
        private(set) var candidates: [Candidate] = []
        private(set) var matches: [Match] = []
        private(set) var isSearching = false

        // a plain bool, not keyed by row like other children - attaching and
        // merging both rewrite the whole screen's identity at once
        private(set) var saving = false
        private(set) var failure: Failure?

        // nonisolated: a static inside a @MainActor type inherits that
        // isolation, and an immutable Int has nothing to protect
        nonisolated static let limit = 10

        private let registry: Compositor.Registry
        private let assets: Compositor.Assets
        private let database: DatabaseClient

        init(registry: Compositor.Registry, assets: Compositor.Assets, database: DatabaseClient) {
            self.registry = registry
            self.assets = assets
            self.database = database
        }

        func clear() {
            failure = nil
        }

        var isAmbiguous: Bool { !candidates.isEmpty }

        // failing here doesn't set failure - the caller settles instead on
        // false, which is the same outcome as finding nothing
        func load(_ ids: [SeriesRecord.ID]) async -> Bool {
            do {
                let rows = try await database.reader.read { db in
                    try Self.candidates(for: ids, in: db)
                }

                candidates = rows.map(row(from:))
                return true
            } catch {
                AppLog.shared.log(
                    "candidates failed - \(error)", level: .error, category: "details")
                return false
            }
        }

        func dismiss() {
            candidates = []
        }

        // no query: ranked by title similarity across both sides' full title
        // pools, so a romaji copy still finds its english twin. with a query:
        // fts decides who is in, similarity only decides the order
        func search(_ query: String, for id: SeriesRecord.ID) async {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)

            isSearching = true
            defer { isSearching = false }

            do {
                let (scored, rows) = try await database.reader.read { db in
                    let scored = try Self.scored(for: id, matching: text, in: db)
                    return (scored, try Self.candidates(for: scored.map(\.id), in: db))
                }

                // re-run per keystroke and the previous one cancelled - a late
                // result must not overwrite a newer query's
                guard !Task.isCancelled else { return }

                // rows come back in table order - scored is what's sorted
                let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

                matches = scored.compactMap { match in
                    guard let row = byId[match.id.rawValue] else { return nil }
                    return self.match(from: row, score: match.score)
                }
            } catch {
                AppLog.shared.log(
                    "merge candidates failed - \(error)", level: .error, category: "details")
                matches = []
            }
        }

        func reparent(_ held: SeriesRecord.ID, into target: SeriesRecord.ID) async -> Bool {
            saving = true
            defer { saving = false }

            do {
                try await database.writer.write { db in
                    try Self.reparent(from: held, into: target, in: db)
                }
                return true
            } catch {
                failure = Failure(error, fallback: "Couldn't Load Series")
                return false
            }
        }

        // the target's own preferences, status and ordering stay untouched
        func merge(_ series: SeriesRecord.ID, into target: SeriesRecord.ID) async -> Bool {
            saving = true
            defer { saving = false }

            do {
                try await database.writer.write { db in
                    try Self.merge(from: series, into: target, in: db)
                }
                matches = []
                AppLog.shared.log(
                    "merged series \(series.rawValue) into \(target.rawValue)",
                    category: "details"
                )
                return true
            } catch {
                failure = Failure(error, fallback: "Couldn't Merge Series")
                AppLog.shared.log(
                    "merge into \(target.rawValue) FAILED - \(error)", level: .error,
                    category: "details")
                return false
            }
        }

        private func row(from row: Row) -> Candidate {
            Candidate(
                id: row.id,
                title: row.title,
                authors: row.authors,
                synopsis: row.synopsis,
                cover: artwork(row.cover, path: row.path),
                referer: referer(row.sourceSlug),
                read: row.read,
                total: row.total,
                lastReadDate: row.lastReadDate > .distantPast ? row.lastReadDate : nil,
                addedDate: row.addedDate
            )
        }

        private func match(from row: Row, score: Double) -> Match {
            Match(
                id: row.id,
                title: row.title,
                authors: row.authors,
                synopsis: row.synopsis,
                cover: artwork(row.cover, path: row.path),
                referer: referer(row.sourceSlug),
                status: row.status,
                publication: row.publication,
                origins: row.origins,
                read: row.read,
                total: row.total,
                score: score
            )
        }

        // not memoised like the displayed cover - these lists are built fresh
        // per prompt and thrown away, no session-long cache key to keep stable
        private func artwork(_ remote: URL?, path: String?) -> URL? {
            assets.local(for: path) ?? remote
        }

        private func referer(_ slug: String?) -> URL? {
            slug.flatMap { registry.source(slug: $0) }?.descriptor.referer
        }
    }
}

extension DetailsComposer {
    func attach(to target: Int64) async {
        let id = SeriesRecord.ID(rawValue: target)
        identity.dismiss()

        guard let held else {
            await store(into: id)
            return
        }

        guard await identity.reparent(held, into: id) else { return }

        self.held = nil
        observe(id)
    }

    // not the same series after all, so it lands where an unmatched open lands
    func separate() async {
        identity.dismiss()
        await settle()
    }

    func merge(into target: Int64) async {
        guard let seriesId else { return }
        let id = SeriesRecord.ID(rawValue: target)
        guard id != seriesId else { return }

        guard await identity.merge(seriesId, into: id) else { return }

        // the observed row was just deleted, so the screen re-points at the
        // series everything now belongs to
        observe(id)
    }
}

extension DetailsComposer.Identity {
    struct Candidate: Identifiable, Hashable {
        let id: Int64
        let title: String
        let authors: String?
        let synopsis: String?
        let cover: URL?
        let referer: URL?
        let read: Int
        let total: Int
        let lastReadDate: Date?
        let addedDate: Date

        var started: Bool { read > 0 }

        var meta: String {
            if let lastReadDate {
                return "Last read \(lastReadDate.formatted(.relative(presentation: .numeric)))"
            }
            return "Added \(addedDate.formatted(.dateTime.month(.abbreviated).year()))"
        }
    }

    struct Match: Identifiable, Hashable {
        let id: Int64
        let title: String
        let authors: String?
        let synopsis: String?
        let cover: URL?
        let referer: URL?
        let status: Status
        let publication: Publication
        let origins: Int
        let read: Int
        let total: Int
        let score: Double

        var match: Int { Int((score * 100).rounded()) }
    }

    struct Row: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let title: String
        let authors: String?
        let synopsis: String?
        let cover: URL?
        let path: String?
        let read: Int
        let total: Int
        let lastReadDate: Date
        let addedDate: Date
        let publication: Publication
        let status: Status
        let origins: Int
        let sourceSlug: String?
    }
}

extension DetailsComposer.Identity {
    nonisolated static func candidates(
        for ids: [SeriesRecord.ID],
        in db: Database
    ) throws -> [Row] {
        guard !ids.isEmpty else { return [] }

        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT
                v.\(RichfulEntryView.Columns.seriesId.name) AS id,
                v.\(RichfulEntryView.Columns.title.name) AS title,
                v.\(RichfulEntryView.Columns.authors.name) AS authors,
                v.\(RichfulEntryView.Columns.synopsis.name) AS synopsis,
                v.\(RichfulEntryView.Columns.cover.name) AS cover,
                v.\(RichfulEntryView.Columns.path.name) AS path,
                v.\(RichfulEntryView.Columns.readChapterCount.name) AS read,
                v.\(RichfulEntryView.Columns.totalChapterCount.name) AS total,
                v.\(RichfulEntryView.Columns.lastReadDate.name) AS lastReadDate,
                v.\(RichfulEntryView.Columns.addedDate.name) AS addedDate,
                v.\(RichfulEntryView.Columns.publication.name) AS publication,
                (SELECT sr.\(SeriesRecord.Columns.status.name)
                   FROM \(SeriesRecord.databaseTableName) sr
                  WHERE sr.id = v.\(RichfulEntryView.Columns.seriesId.name)) AS status,
                (SELECT COUNT(*)
                   FROM \(OriginRecord.databaseTableName) oc
                  WHERE oc.\(OriginRecord.Columns.seriesId.name) = v.\(RichfulEntryView.Columns.seriesId.name)) AS origins,
                (SELECT src.\(SourceRecord.Columns.slug.name)
                   FROM \(OriginRecord.databaseTableName) o
                   JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
                  WHERE o.\(OriginRecord.Columns.seriesId.name) = v.\(RichfulEntryView.Columns.seriesId.name)
                  ORDER BY o.\(OriginRecord.Columns.priority.name) ASC LIMIT 1) AS sourceSlug
            FROM \(RichfulEntryView.databaseTableName) v
            WHERE v.\(RichfulEntryView.Columns.seriesId.name) IN (\(placeholders))
            """

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids.map(\.rawValue)))
    }

    // runs in swift - sqlite has no string-distance function to push this
    // into. the cap applies only to the unqueried list, a query has already
    // narrowed by hand
    nonisolated static func scored(
        for id: SeriesRecord.ID,
        matching query: String,
        in db: Database
    ) throws -> [(id: SeriesRecord.ID, score: Double)] {
        let own =
            try TitleRecord
            .select(TitleRecord.Columns.value, as: String.self)
            .filter(TitleRecord.Columns.seriesId == id)
            .fetchAll(db)
        guard !own.isEmpty else { return [] }

        var sql = """
            SELECT t.\(TitleRecord.Columns.seriesId.name) AS seriesId,
                   t.\(TitleRecord.Columns.value.name) AS value
            FROM \(TitleRecord.databaseTableName) t
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = t.\(TitleRecord.Columns.seriesId.name)
            WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1 AND s.id != ?
            """
        var arguments: StatementArguments = [id]

        if !query.isEmpty {
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
            sql += """

                AND s.id IN (
                    SELECT rowid FROM \(SeriesFTS5View.databaseTableName)
                    WHERE \(SeriesFTS5View.databaseTableName) MATCH ?
                )
                """
            arguments += [pattern]
        }

        let rows = try GRDB.Row.fetchAll(db, sql: sql, arguments: arguments)

        var pools: [Int64: [String]] = [:]
        for row in rows {
            pools[row["seriesId"], default: []].append(row["value"])
        }

        let scored =
            pools
            .map { id, titles in
                let best =
                    titles
                    .flatMap { title in own.map { Similarity.score($0, title) } }
                    .max() ?? 0
                return (id: SeriesRecord.ID(rawValue: id), score: best)
            }
            .sorted { $0.score > $1.score }

        return query.isEmpty ? Array(scored.prefix(limit)) : scored
    }

    nonisolated static func merge(
        from series: SeriesRecord.ID,
        into target: SeriesRecord.ID,
        in db: Database
    ) throws {
        try DetailsComposer.Library.adopt(from: series, into: target, in: db)
        try reparent(from: series, into: target, in: db)
        try propagate(for: target, in: db)
    }

    // metadata/titles/covers move by seriesId, not originId: a row whose
    // supplier was removed carries no originId, and an origin-keyed sweep
    // would leave it for the delete below to cascade away. UPDATE OR IGNORE
    // because the target may already hold the same supplier/title/url, and a
    // true duplicate is correct to drop
    nonisolated static func reparent(
        from series: SeriesRecord.ID,
        into target: SeriesRecord.ID,
        in db: Database
    ) throws {
        var next =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(\(OriginRecord.Columns.priority.name)), -1) + 1
                    FROM \(OriginRecord.databaseTableName)
                    WHERE \(OriginRecord.Columns.seriesId.name) = ?
                    """,
                arguments: [target]
            ) ?? 0

        let origins =
            try OriginRecord
            .filter(OriginRecord.Columns.seriesId == series)
            .order(OriginRecord.Columns.priority.asc, OriginRecord.Columns.id.asc)
            .fetchAll(db)

        for origin in origins {
            guard let originId = origin.id else { continue }

            try db.execute(
                sql: """
                    UPDATE \(OriginRecord.databaseTableName)
                    SET \(OriginRecord.Columns.seriesId.name) = ?, \(OriginRecord.Columns.priority.name) = ?
                    WHERE id = ?
                    """,
                arguments: [target, next, originId]
            )
            next += 1
        }

        for table in [
            MetadataRecord.databaseTableName,
            TitleRecord.databaseTableName,
            CoverRecord.databaseTableName,
        ] {
            try db.execute(
                sql: "UPDATE OR IGNORE \(table) SET seriesId = ? WHERE seriesId = ?",
                arguments: [target, series]
            )
        }

        try db.execute(
            sql: "DELETE FROM \(SeriesRecord.databaseTableName) WHERE id = ?",
            arguments: [series]
        )
    }

    // marks everything at or below the furthest-read number as read, over the
    // union of both chapter sets. monotonic, so nothing already further along
    // moves back
    nonisolated static func propagate(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws {
        let sql = """
            SELECT DISTINCT c.\(ChapterRecord.Columns.number.name)
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
              AND c.\(ChapterRecord.Columns.number.name) <= (
                SELECT MAX(r.\(ChapterRecord.Columns.number.name))
                FROM \(ChapterRecord.databaseTableName) r
                JOIN \(OriginRecord.databaseTableName) ro ON ro.id = r.\(ChapterRecord.Columns.originId.name)
                WHERE ro.\(OriginRecord.Columns.seriesId.name) = ?
                  AND r.\(ChapterRecord.Columns.progress.name) >= 1
              )
            """
        let numbers = try Double.fetchAll(db, sql: sql, arguments: [id, id])
        try ChapterRecord.apply(progress: 1.0, toNumbers: numbers, in: id, monotonic: true, db: db)

        // a merge can raise the number past what the service last heard - the
        // same intent is recorded here as anywhere else progress is written
        try SeriesTrackerRecord.enqueue(for: id, in: db)
    }
}

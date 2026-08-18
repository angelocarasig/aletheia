//
//  Compositor+Assets.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB
import Tagged

extension Compositor {
    struct Assets: Sendable {
        private let downloader: CoverDownloader

        // shared with the chapter downloader rather than built twice: one store
        // means one place that knows the on-disk layout, and the sweep's
        // fixed-depth enumeration is part of that layout
        let store: any AssetStoring

        init(
            database: DatabaseClient,
            registry: Registry,
            network: NetworkConfiguration,
            log: AppLog = .shared
        ) {
            let store = AssetStore(network: network, log: log)
            self.store = store
            self.downloader = CoverDownloader(
                database: database,
                registry: registry,
                store: store,
                log: log
            )
        }

        // the work is owned by the actor, not by whoever asked for it - a screen
        // that goes away two seconds after opening must not cancel its downloads
        func enqueue(series: SeriesRecord.ID) {
            guard !Constants.App.isPreview else { return }
            Task { await downloader.enqueue(series) }
        }

        func sweep() {
            guard !Constants.App.isPreview else { return }
            Task { await downloader.sweep() }
        }

        func local(for path: String?) -> URL? {
            store.resolve(path)
        }
    }
}

actor CoverDownloader {
    private let database: DatabaseClient
    private let registry: Compositor.Registry
    private let store: any AssetStoring
    private let log: AppLog

    private var inFlight: Set<Int64> = []
    private var failures: [Int64: Int] = [:]

    init(
        database: DatabaseClient,
        registry: Compositor.Registry,
        store: any AssetStoring,
        log: AppLog
    ) {
        self.database = database
        self.registry = registry
        self.store = store
        self.log = log
    }

    private enum Limits {
        static let attempts = 3
        static let backlog = 200
    }

    func enqueue(_ series: SeriesRecord.ID) async {
        let pending =
            (try? await database.reader.read { db in
                try Self.pending(for: series, in: db)
            }) ?? []

        await download(pending)
    }

    // launch order matters: clean() has already cascaded away disposable series,
    // and that cascade is what manufactures the orphans this collects
    func sweep() async {
        do {
            let live = try await database.reader.read { db in
                try CoverRecord.stored(in: db)
            }

            let removed = try store.sweep(CoverRecord.storage, keeping: live)
            log.log("swept \(removed) orphaned cover file(s)", category: "assets")

            let missing = live.filter { store.resolve($0) == nil }
            if !missing.isEmpty {
                try await database.writer.write { db in
                    try CoverRecord.forget(Array(missing), in: db)
                }
                log.log(
                    "cleared \(missing.count) cover path(s) with no file", level: .warning,
                    category: "assets")
            }
        } catch {
            // a failed read must never be mistaken for an empty keep set - that
            // would delete every downloaded cover the user has
            log.log("sweep ABORTED - \(error)", category: "assets")
            return
        }

        // not `try?`: a decode failure here returns an empty backlog, which is
        // indistinguishable from "nothing to download" and silently stops every
        // cover on the device from ever being fetched. it has already happened
        // once, when Pending grew a column this query did not select
        let backlog: [Pending]
        do {
            backlog = try await database.reader.read { db in
                try Self.backlog(limit: Limits.backlog, in: db)
            }
        } catch {
            log.log("backlog read FAILED - \(error)", level: .error, category: "assets")
            return
        }

        if !backlog.isEmpty {
            log.log("downloading \(backlog.count) missing cover(s)", category: "assets")
        }

        await download(backlog)
    }

    // the descending fallback the pool always implied and never had. covers are
    // add-only and a series points at exactly one of them, so a preferred cover
    // that turns out to be gone left the series with no artwork while a working
    // sibling sat in the same table, reachable only by opening the covers sheet
    // and picking it by hand.
    //
    // only when the dead one is the PREFERRED one: a spare cover 404ing changes
    // nothing about what is on screen, and repointing on it would overrule a
    // choice the reader made
    private func promote(from row: Pending) async {
        let dead = row.id
        let series = row.seriesId
        let exhausted = failures

        do {
            let promoted: Int64? = try await database.writer.write { db in
                guard let current = try SeriesRecord.fetchOne(db, key: series),
                    current.preferredCoverId?.rawValue == dead
                else { return nil }

                // ordered the way the pool was built, which is quality
                // descending - so the first survivor is the best one left. a
                // cover already on disk wins outright over one still to try
                let alternates =
                    try CoverRecord
                    .filter(CoverRecord.Columns.seriesId == series)
                    .filter(CoverRecord.Columns.id != dead)
                    .order(CoverRecord.Columns.id)
                    .fetchAll(db)

                let next =
                    alternates.first { $0.path != nil }
                    ?? alternates.first {
                        ($0.id?.rawValue).map { !exhausted.keys.contains($0) } ?? false
                    }
                    ?? alternates.first

                guard let next, let id = next.id else { return nil }

                _ =
                    try SeriesRecord
                    .filter(key: series)
                    .updateAll(db, SeriesRecord.Columns.preferredCoverId.set(to: id.rawValue))

                return id.rawValue
            }

            guard let promoted else {
                log.log("cover \(dead) is gone and the series has no alternate", category: "assets")
                return
            }

            log.log(
                "cover \(dead) is gone - series \(series) promoted to \(promoted)",
                category: "assets")

            // the promoted one may have no file yet, and nothing else will come
            // back for it: this pass has already filtered its queue
            await enqueue(SeriesRecord.ID(rawValue: series))
        } catch {
            log.log(
                "could not promote past cover \(dead) - \(error)", level: .error, category: "assets"
            )
        }
    }

    private func download(_ rows: [Pending]) async {
        let queued = rows.filter { row in
            !inFlight.contains(row.id) && (failures[row.id] ?? 0) < Limits.attempts
        }
        guard !queued.isEmpty else { return }

        queued.forEach { inFlight.insert($0.id) }
        defer { queued.forEach { inFlight.remove($0.id) } }

        var written: [Int64: String] = [:]

        for row in queued {
            // a disconnected origin has no source to speak for it, so the request
            // goes out with the pinned agent alone - the same bare request it
            // made before headers were a source's business
            let headers =
                row.sourceSlug
                .flatMap { registry.source(slug: $0) }?
                .requestHeaders
                ?? ["User-Agent": Constants.Network.userAgent]

            let asset = Asset(
                key: row.url.absoluteString,
                parts: [row.url],
                folder: CoverRecord.storage,
                headers: headers
            )

            do {
                written[row.id] = try await store.store(asset)
            } catch {
                failures[row.id, default: 0] += 1
                log.log("cover \(row.id) failed - \(error)", level: .error, category: "assets")

                // a url that is GONE is not a url to try again. counting attempts
                // against it burns three requests a launch forever, and - worse -
                // leaves the series pointing at artwork that can never arrive.
                // the pool already holds the alternates, so the answer is to
                // repoint rather than to keep asking
                if Self.isGone(error) {
                    failures[row.id] = Limits.attempts
                    await promote(from: row)
                }
            }
        }

        guard !written.isEmpty else { return }

        // the write closure runs off this actor, so it takes a snapshot rather
        // than the mutable accumulator itself
        let paths = written

        // one transaction, not one per cover: each write wakes the details
        // observation and both entry views
        do {
            try await database.writer.write { db in
                for (id, path) in paths {
                    _ =
                        try CoverRecord
                        .filter(key: id)
                        .updateAll(db, CoverRecord.Columns.path.set(to: path))
                }
            }
        } catch {
            log.log(
                "could not record \(written.count) cover path(s) - \(error)", level: .error,
                category: "assets")
        }
    }
}

extension CoverDownloader {
    // 404 and 410 are the two answers that mean "not coming back". everything
    // else - a timeout, a 500, no connection - is the same url on a bad day, and
    // NetworkError.isRetryable cannot tell them apart because it is true for
    // every status code
    fileprivate static func isGone(_ error: Error) -> Bool {
        guard case NetworkError.badResponse(let status, _) = error else { return false }
        return status == 404 || status == 410
    }

    fileprivate struct Pending: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let seriesId: Int64
        let url: URL
        let sourceSlug: String?
    }

    // every join is LEFT: metadataId, originId and sourceId are each ON DELETE
    // SET NULL, so a cover whose supplier is gone yields no referer and is
    // downloaded without one
    fileprivate static func pending(for series: SeriesRecord.ID, in db: Database) throws
        -> [Pending]
    {
        let sql = """
            SELECT
                c.id AS id,
                c.\(CoverRecord.Columns.seriesId.name) AS seriesId,
                c.\(CoverRecord.Columns.url.name) AS url,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(CoverRecord.databaseTableName) c
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = c.\(CoverRecord.Columns.seriesId.name)
            LEFT JOIN \(MetadataRecord.databaseTableName) md ON md.id = c.\(CoverRecord.Columns.metadataId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = md.\(MetadataRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE c.\(CoverRecord.Columns.seriesId.name) = ?
              AND c.\(CoverRecord.Columns.path.name) IS NULL
            ORDER BY (c.id = s.\(SeriesRecord.Columns.preferredCoverId.name)) DESC, c.id ASC
            """

        return try Pending.fetchAll(db, sql: sql, arguments: [series])
    }

    // the backstop for whatever the write path missed, so it is bounded and
    // ordered by what the user is most likely to look at
    fileprivate static func backlog(limit: Int, in db: Database) throws -> [Pending] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(CoverRecord.Columns.seriesId.name) AS seriesId,
                c.\(CoverRecord.Columns.url.name) AS url,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(CoverRecord.databaseTableName) c
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = c.\(CoverRecord.Columns.seriesId.name)
            LEFT JOIN \(MetadataRecord.databaseTableName) md ON md.id = c.\(CoverRecord.Columns.metadataId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = md.\(MetadataRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE c.\(CoverRecord.Columns.path.name) IS NULL
            ORDER BY
                s.\(SeriesRecord.Columns.inLibrary.name) DESC,
                s.\(SeriesRecord.Columns.lastReadDate.name) DESC,
                c.id ASC
            LIMIT ?
            """

        return try Pending.fetchAll(db, sql: sql, arguments: [limit])
    }
}

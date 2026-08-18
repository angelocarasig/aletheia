//
//  Compositor+Downloads.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Observation
import Tagged

// class not struct: Observation tracks per-instance property reads, so a struct
// entry in the dictionary would invalidate every reader on any page landing. v2
// shipped exactly that (DownloadCoordinator.downloadProgress: a struct array
// behind one observable property).
//
// call site rule: ask the collection WHICH download, ask the item HOW FAR -
// `queue.index[id]?.pagesDone` inline reads the collection, not the item
@MainActor
@Observable
final class Download: Identifiable {
    let id: ChapterRecord.ID
    let title: String
    let series: String

    private(set) var state: State = .queued
    private(set) var pagesDone = 0
    private(set) var pagesTotal = 0

    enum State: Equatable {
        case queued
        case preparing
        case downloading
        case failed(String)
    }

    init(id: ChapterRecord.ID, title: String, series: String) {
        self.id = id
        self.title = title
        self.series = series
    }

    var fraction: Double {
        guard pagesTotal > 0 else { return 0 }
        return min(1, Double(pagesDone) / Double(pagesTotal))
    }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    // Observation fires on assignment, not on change, so the guard below is a
    // hand-rolled distinctUntilChanged
    func advance(_ done: Int, of total: Int) {
        if state != .downloading { state = .downloading }
        guard done != pagesDone || total != pagesTotal else { return }
        pagesDone = done
        pagesTotal = total
    }

    func prepare() {
        guard state != .preparing else { return }
        state = .preparing
        pagesDone = 0
        pagesTotal = 0
    }

    func fail(_ reason: String) {
        guard state != .failed(reason) else { return }
        state = .failed(reason)
    }

    func requeue() {
        guard state != .queued else { return }
        state = .queued
        pagesDone = 0
        pagesTotal = 0
    }
}

extension Compositor {
    @MainActor
    @Observable
    final class Downloads {
        private let database: DatabaseClient
        private let registry: Registry
        private let worker: ChapterDownloader
        private let log: AppLog

        private(set) var order: [Download] = []
        private(set) var index: [ChapterRecord.ID: Download] = [:]

        // stored rather than derived: folding `order` to compute these would read
        // every item's progress and put the invalidation storm back
        private(set) var completed = 0
        private(set) var failures = 0
        private(set) var total = 0

        @ObservationIgnored private var run: Task<Void, Never>?
        @ObservationIgnored private var pending: [Work] = []
        @ObservationIgnored private var inFlight: [String: Int] = [:]
        @ObservationIgnored private var slots: [Int64: String] = [:]
        @ObservationIgnored private var drift: [Int64: Int64] = [:]
        @ObservationIgnored private var halted = false

        // lazy since these closures capture self, which the nonisolated init cannot
        //
        // three chapters fetching page lists at once with nothing to report yet is
        // a real gap - a mangafire page list is a ~24s render - which drift covers
        @ObservationIgnored private lazy var task = ContinuedTask(
            identifier: Constants.Tasks.downloads,
            log: log,
            tick: { [weak self] in
                guard let self, self.isRunning, self.total > 0 else { return nil }
                return ContinuedTask.Tick(
                    done: self.units,
                    total: Int64(self.total) * Limits.scale,
                    subtitle: "\(self.completed) of \(self.total)"
                )
            },
            drift: { [weak self] in
                guard let self else { return }
                for (id, current) in self.drift {
                    self.drift[id] = current + (Limits.ceiling - current) / 4
                }
            }
        )

        var isRunning: Bool { run != nil }

        private enum Limits {
            // pages within a chapter are serial, so one chapter in flight is one
            // request at its host - 3 matches HostGate's per-host cap exactly, so
            // nothing parks at the gate and more page parallelism would only queue behind it
            static let width = 3

            static let scale: Int64 = 1000
            static let ceiling: Int64 = 900
        }

        // nonisolated so Compositor can build this off the main actor during bootstrap
        nonisolated init(
            database: DatabaseClient,
            registry: Registry,
            store: any AssetStoring,
            log: AppLog = .shared
        ) {
            self.database = database
            self.registry = registry
            self.worker = ChapterDownloader(database: database, store: store, log: log)
            self.log = log
        }

        // MARK: Enqueue

        func enqueue(chapter id: ChapterRecord.ID) {
            enqueue(chapters: [id])
        }

        func enqueue(chapters ids: [ChapterRecord.ID]) {
            let wanted = ids.filter { index[$0] == nil || index[$0]?.isFailed == true }
            guard !wanted.isEmpty else { return }

            Task { [weak self] in
                guard let self else { return }
                let work = await self.resolve(wanted)
                self.admit(work)
            }
        }

        func enqueue(unreadFor series: SeriesRecord.ID) {
            Task { [weak self] in
                guard let self else { return }
                let ids = await self.unread(for: series)
                guard !ids.isEmpty else { return }
                self.admit(await self.resolve(ids))
            }
        }

        private func admit(_ work: [Work]) {
            let fresh = work.filter { index[$0.id] == nil }
            let retried = work.filter { index[$0.id]?.isFailed == true }
            guard !fresh.isEmpty || !retried.isEmpty else { return }

            // batched: one append rather than one invalidation per chapter
            let items = fresh.map { Download(id: $0.id, title: $0.title, series: $0.series) }
            order.append(contentsOf: items)
            for item in items { index[item.id] = item }
            total += fresh.count

            // a retry never left the queue, so it's already counted in `total` -
            // only its recorded failure comes back off
            for item in retried {
                index[item.id]?.requeue()
                failures = max(0, failures - 1)
            }

            pending.append(contentsOf: fresh + retried)
            persist()
            drain()
        }

        // MARK: Cancel and delete

        func cancel(chapter id: ChapterRecord.ID) {
            pending.removeAll { $0.id == id }
            discard(id)
            persist()
            Task { [worker] in await worker.cancel(id) }
        }

        func cancelAll() {
            guard !order.isEmpty else { return }
            log.log("queue cancelled at \(completed) of \(total)", category: "downloads")

            pending = []
            order = []
            index = [:]
            slots = [:]
            inFlight = [:]
            drift = [:]
            total = 0
            completed = 0
            failures = 0
            persist()

            run?.cancel()
            Task { [worker] in await worker.cancelAll() }
        }

        func delete(chapter id: ChapterRecord.ID) {
            Task { [weak self] in
                guard let self else { return }
                await self.worker.forget([id])
                self.sweep()
            }
        }

        func delete(for series: SeriesRecord.ID) {
            Task { [weak self] in
                guard let self else { return }
                let ids = await self.downloaded(for: series)
                guard !ids.isEmpty else { return }
                await self.worker.forget(ids)
                self.sweep()
            }
        }

        // MARK: Launch

        // progress state is derivable, but "these forty chapters were queued" is not -
        // only the intent list needs to survive a kill
        func restore() {
            guard !Constants.App.isPreview else { return }
            let ids =
                (UserDefaults.standard.array(forKey: Preferences.Key.downloadQueue) as? [Int])?
                .map { ChapterRecord.ID(rawValue: Int64($0)) } ?? []

            guard !ids.isEmpty else { return }

            log.log("restoring \(ids.count) queued chapter(s)", category: "downloads")
            enqueue(chapters: ids)
        }

        func sweep() {
            guard !Constants.App.isPreview else { return }
            let queued = order.map(\.id)
            Task { [worker] in await worker.sweep(alsoKeeping: queued) }
        }

        func register() {
            task.register { [weak self] in self?.cancelAll() }
        }

        // MARK: The walk

        private func drain() {
            guard run == nil else { return }
            halted = false

            run = Task { [weak self] in
                await self?.walk()
                self?.finish()
            }

            task.submit(title: "Downloading Chapters", subtitle: "\(completed) of \(total)")
        }

        private func walk() async {
            await withTaskGroup(of: ChapterDownloader.Outcome.self) { group in
                fill(&group)

                while let outcome = await group.next() {
                    settle(outcome)
                    guard !Task.isCancelled else { continue }
                    fill(&group)
                }
            }
        }

        private func fill(_ group: inout TaskGroup<ChapterDownloader.Outcome>) {
            while let work = take() {
                dispatch(work)

                // captured rather than looked up inside the closure - reading
                // `index` per page would subscribe this task to membership changes
                let item = index[work.id]
                group.addTask { [worker] in
                    await worker.store(work) { done, total in
                        Task { @MainActor in item?.advance(done, of: total) }
                    }
                }
            }
        }

        private func take() -> Work? {
            guard !halted else { return nil }
            guard
                let next = pending.firstIndex(where: {
                    (inFlight[$0.sourceSlug] ?? 0) < Limits.width
                })
            else { return nil }

            return pending.remove(at: next)
        }

        private func dispatch(_ work: Work) {
            inFlight[work.sourceSlug, default: 0] += 1
            slots[work.id.rawValue] = work.sourceSlug
            drift[work.id.rawValue] = 0
            index[work.id]?.prepare()
            task.advance()
        }

        private func settle(_ outcome: ChapterDownloader.Outcome) {
            switch outcome {
            case .stored(let id, let pages):
                completed += 1
                discard(id)
                log.log("chapter \(id.rawValue) stored, \(pages) page(s)", category: "downloads")

            case .cancelled(let id):
                discard(id)

            case .failed(let id, let reason):
                failures += 1
                release(id)
                index[id]?.fail(reason)
                log.log(
                    "chapter \(id.rawValue) FAILED - \(reason)", level: .error,
                    category: "downloads")

            case .noSpace(let id):
                // halt rather than let every remaining chapter fail the same way -
                // what's left stays queued, so freeing space resumes it all
                halted = true
                failures += 1
                release(id)
                index[id]?.fail("Not enough storage left.")
                log.log("queue halted - not enough storage", category: "downloads")
            }

            persist()
            task.advance()
        }

        private func finish() {
            run = nil
            inFlight = [:]
            slots = [:]
            drift = [:]

            // a retry admitted between walk() finishing and `run` clearing here
            // would otherwise find drain() guarded with nothing to pick it up
            guard pending.isEmpty else { return drain() }

            if order.isEmpty {
                total = 0
                completed = 0
                failures = 0
            }

            task.finish()
        }

        // MARK: State helpers

        private func discard(_ id: ChapterRecord.ID) {
            release(id)
            index[id] = nil
            order.removeAll { $0.id == id }
        }

        private func release(_ id: ChapterRecord.ID) {
            drift[id.rawValue] = nil
            guard let slug = slots.removeValue(forKey: id.rawValue) else { return }
            inFlight[slug] = max(0, (inFlight[slug] ?? 1) - 1)
        }

        // monotonic by construction - NSProgress going backwards reads worse than not moving
        private var units: Int64 {
            let live = order.reduce(Int64(0)) { running, item in
                guard slots[item.id.rawValue] != nil else { return running }
                let real = Int64(item.fraction * Double(Limits.ceiling))
                return running + max(real, drift[item.id.rawValue] ?? 0)
            }

            return min(Int64(completed) * Limits.scale + live, Int64(total) * Limits.scale)
        }

        private func persist() {
            UserDefaults.standard.set(
                order.map { Int($0.id.rawValue) },
                forKey: Preferences.Key.downloadQueue
            )
        }

    }
}

// MARK: - The work list

extension Compositor.Downloads {
    struct Work: Sendable {
        let id: ChapterRecord.ID
        let originId: OriginRecord.ID
        let slug: String
        let originSlug: String
        let sourceSlug: String
        let source: Source
        let title: String
        let series: String
    }

    private struct Row: Decodable, FetchableRecord {
        let id: Int64
        let originId: Int64
        let slug: String
        let title: String
        let originSlug: String
        let sourceSlug: String
        let series: String
    }

    private func resolve(_ ids: [ChapterRecord.ID]) async -> [Work] {
        let rows =
            (try? await database.reader.read { db in
                try Self.rows(for: ids, in: db)
            }) ?? []

        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        return ids.compactMap { id -> Work? in
            guard let row = byId[id.rawValue],
                let source = registry.source(slug: row.sourceSlug)
            else { return nil }

            return Work(
                id: ChapterRecord.ID(rawValue: row.id),
                originId: OriginRecord.ID(rawValue: row.originId),
                slug: row.slug,
                originSlug: row.originSlug,
                sourceSlug: row.sourceSlug,
                source: source,
                title: row.title,
                series: row.series
            )
        }
    }

    private func unread(for series: SeriesRecord.ID) async -> [ChapterRecord.ID] {
        (try? await database.reader.read { db in
            try Self.unread(for: series, in: db)
        }) ?? []
    }

    private func downloaded(for series: SeriesRecord.ID) async -> [ChapterRecord.ID] {
        (try? await database.reader.read { db in
            try Self.downloaded(for: series, in: db)
        }) ?? []
    }

    nonisolated private static func rows(for ids: [ChapterRecord.ID], in db: Database) throws
        -> [Row]
    {
        let list = ids.map { String($0.rawValue) }.joined(separator: ",")
        guard !list.isEmpty else { return [] }

        let sql = """
            SELECT
                c.id AS id,
                c.\(ChapterRecord.Columns.originId.name) AS originId,
                c.\(ChapterRecord.Columns.slug.name) AS slug,
                c.\(ChapterRecord.Columns.title.name) AS title,
                o.\(OriginRecord.Columns.slug.name) AS originSlug,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                e.\(EntryView.Columns.title.name) AS series
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            JOIN \(SourceRecord.databaseTableName) src
              ON src.id = o.\(OriginRecord.Columns.sourceId.name)
             AND src.\(SourceRecord.Columns.installed.name) = 1
             AND src.\(SourceRecord.Columns.disabled.name) = 0
            JOIN \(EntryView.databaseTableName) e
              ON e.\(EntryView.Columns.seriesId.name) = o.\(OriginRecord.Columns.seriesId.name)
            WHERE c.id IN (\(list))
              AND c.\(ChapterRecord.Columns.path.name) IS NULL
            """

        return try Row.fetchAll(db, sql: sql)
    }

    // rank 1 only: the copy the chapter list would show is the copy worth storing
    nonisolated private static func unread(for series: SeriesRecord.ID, in db: Database) throws
        -> [ChapterRecord.ID]
    {
        let sql = """
            SELECT b.chapterId AS id
            FROM \(BestChapterView.databaseTableName) b
            JOIN \(ChapterRecord.databaseTableName) c ON c.id = b.chapterId
            WHERE b.seriesId = ?
              AND b.rank = 1
              AND b.isVisible = 1
              AND b.progress < 1
              AND c.\(ChapterRecord.Columns.path.name) IS NULL
            ORDER BY b.number ASC
            """

        return try Int64.fetchAll(db, sql: sql, arguments: [series.rawValue])
            .map { ChapterRecord.ID(rawValue: $0) }
    }

    nonisolated private static func downloaded(for series: SeriesRecord.ID, in db: Database) throws
        -> [ChapterRecord.ID]
    {
        let sql = """
            SELECT c.id AS id
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
              AND c.\(ChapterRecord.Columns.path.name) IS NOT NULL
            """

        return try Int64.fetchAll(db, sql: sql, arguments: [series.rawValue])
            .map { ChapterRecord.ID(rawValue: $0) }
    }
}

// MARK: - The worker

actor ChapterDownloader {
    private let database: DatabaseClient
    private let store: any AssetStoring
    private let log: AppLog

    // unstructured on purpose - a task group's children can't be cancelled
    // individually, and cancel here is per chapter
    private var running: [Int64: Task<Outcome, Never>] = [:]

    init(database: DatabaseClient, store: any AssetStoring, log: AppLog) {
        self.database = database
        self.store = store
        self.log = log
    }

    enum Outcome: Sendable {
        case stored(id: ChapterRecord.ID, pages: Int)
        case failed(id: ChapterRecord.ID, reason: String)
        case cancelled(id: ChapterRecord.ID)
        case noSpace(id: ChapterRecord.ID)
    }

    private enum Limits {
        // mihon's floor - ENOSPC mid-write is what causes an unreadable download
        static let freeSpace: Int64 = 200 * 1024 * 1024
    }

    func store(
        _ work: Compositor.Downloads.Work,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async -> Outcome {
        if let existing = running[work.id.rawValue] { return await existing.value }

        // perform is nonisolated, so this hops off the actor immediately - chapters
        // genuinely run alongside each other rather than serializing on it
        let task = Task { [store, database] in
            await Self.perform(work, store: store, database: database, onProgress: onProgress)
        }

        running[work.id.rawValue] = task
        defer { running[work.id.rawValue] = nil }

        return await task.value
    }

    func cancel(_ id: ChapterRecord.ID) {
        running[id.rawValue]?.cancel()
    }

    func cancelAll() {
        running.values.forEach { $0.cancel() }
    }

    func forget(_ ids: [ChapterRecord.ID]) async {
        do {
            try await database.writer.write { db in
                _ =
                    try ChapterRecord
                    .filter(ids.map(\.rawValue).contains(ChapterRecord.Columns.id))
                    .updateAll(db, ChapterRecord.Columns.path.set(to: nil as String?))
            }
            log.log("cleared \(ids.count) download path(s)", category: "downloads")
        } catch {
            log.log(
                "could not clear \(ids.count) download path(s) - \(error)", level: .error,
                category: "downloads")
        }
    }

    func sweep(alsoKeeping queued: [ChapterRecord.ID]) async {
        do {
            let live = try await database.reader.read { db in
                try ChapterRecord.stored(in: db)
            }

            // a queued chapter has no path yet - stamped only on completion - so it
            // reads as an orphan without this union, and the first launch during a
            // download would delete it
            let working = try await database.reader.read { db in
                try Self.locations(for: queued, in: db)
            }

            let removed = try store.sweep(ChapterRecord.storage, keeping: live.union(working))
            log.log("swept \(removed) orphaned chapter file(s)", category: "downloads")

            let missing = live.filter { store.resolve($0) == nil }
            if !missing.isEmpty {
                try await database.writer.write { db in
                    try ChapterRecord.forget(Array(missing), in: db)
                }
                log.log(
                    "cleared \(missing.count) chapter path(s) with no files", level: .warning,
                    category: "downloads")
            }
        } catch {
            // a failed read must never be mistaken for an empty keep set - that
            // would delete every downloaded chapter the user has, in one launch
            log.log("chapter sweep ABORTED - \(error)", category: "downloads")
        }
    }
}

// MARK: - Performing one chapter

extension ChapterDownloader {
    nonisolated private static func perform(
        _ work: Compositor.Downloads.Work,
        store: any AssetStoring,
        database: DatabaseClient,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async -> Outcome {
        do {
            guard hasSpace() else { return .noSpace(id: work.id) }

            let pages = try await work.source.content(
                seriesSlug: work.originSlug,
                chapterSlug: work.slug
            )
            guard !pages.isEmpty else {
                return .failed(id: work.id, reason: "This chapter has no pages.")
            }

            onProgress(0, pages.count)

            let asset = Asset(
                key: "\(work.originId.rawValue)/\(work.slug)",
                parts: pages.sorted { $0.index < $1.index }.map(\.url),
                folder: ChapterRecord.storage,
                headers: work.source.requestHeaders
            )

            let path = try await store.store(asset) { done, total in
                onProgress(done, total)
            }

            // path is the completion marker for the whole chapter - stamped only
            // after every page lands, which is why they can be written straight
            // to their final home instead of staged and moved
            try await database.writer.write { db in
                _ =
                    try ChapterRecord
                    .filter(key: work.id.rawValue)
                    .updateAll(db, ChapterRecord.Columns.path.set(to: path))
            }

            return .stored(id: work.id, pages: pages.count)
        } catch is CancellationError {
            return .cancelled(id: work.id)
        } catch NetworkError.cancelled {
            return .cancelled(id: work.id)
        } catch {
            return .failed(id: work.id, reason: reason(for: error))
        }
    }

    nonisolated private static func hasSpace() -> Bool {
        let values = try? Constants.Paths.downloads.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )

        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return true }
        return available > Limits.freeSpace
    }

    nonisolated private static func reason(for error: Error) -> String {
        Failure(error, fallback: "Couldn't download").sentence
    }

    // Asset.location is a pure function of the key, so a queued chapter's eventual
    // directory can be computed before it exists
    nonisolated private static func locations(
        for ids: [ChapterRecord.ID],
        in db: Database
    ) throws -> Set<String> {
        guard !ids.isEmpty else { return [] }

        let sql = """
            SELECT
                c.\(ChapterRecord.Columns.originId.name) AS originId,
                c.\(ChapterRecord.Columns.slug.name) AS slug
            FROM \(ChapterRecord.databaseTableName) c
            WHERE c.id IN (\(ids.map { String($0.rawValue) }.joined(separator: ",")))
            """

        let rows = try Row.fetchAll(db, sql: sql)

        return Set(
            rows.map { row in
                let asset = Asset(
                    key: "\(row.originId)/\(row.slug)",
                    parts: [URL(filePath: "/"), URL(filePath: "/")],
                    folder: ChapterRecord.storage,
                    headers: [:]
                )
                return Constants.Paths.relative(asset.location)
            })
    }

    private struct Row: Decodable, FetchableRecord {
        let originId: Int64
        let slug: String
    }
}

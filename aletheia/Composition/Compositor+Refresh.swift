//
//  Compositor+Refresh.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import BackgroundTasks
import GRDB
import UIKit
import Tagged
import Observation

extension Compositor {
    // what screens hold. two jobs, one entry: check a single origin (which is
    // what a Details pull-to-refresh does), or walk the library (which is what
    // the Activity tab watches). both go through the same worker below, so a
    // series refreshed from either place behaves identically - v2 kept two
    // copies of that and they had drifted within a year.
    // see docs/features/background-activity.md 6.4
    @MainActor
    @Observable
    final class Refresh {
        private let database: DatabaseClient
        private let registry: Registry
        private let worker: OriginRefresher
        private let log: AppLog

        private(set) var scope: String?
        private(set) var current: String?
        private(set) var completed = 0
        private(set) var total = 0
        private(set) var failures = 0

        // which series are being checked right now, so a library card can say so
        // on itself. reading this subscribes to the whole set, which is
        // affordable only because it changes per series rather than per tick
        private(set) var active: Set<Int64> = []

        // series a run has not reached yet. a screen opened on one of them can
        // say "queued" rather than looking untouched for the minutes it takes
        // the walk to arrive
        private(set) var queued: Set<Int64> = []

        // origins with a fetch in flight, counted rather than a set: two callers
        // can join one fetch, and the first to return must not clear a mark the
        // second is still standing behind. this is what lets a screen reopened
        // mid-fetch put its own pill back
        private var fetching: [Int64: Int] = [:]

        func isChecking(origin: Int64) -> Bool {
            fetching[origin] != nil
        }

        func isChecking(series: Int64) -> Bool {
            active.contains(series)
        }

        func isQueued(series: Int64) -> Bool {
            queued.contains(series)
        }

        @ObservationIgnored private var run: Task<Void, Never>?

        // the system task, once it grants one. the run does not wait for it and
        // does not need it: this only extends a walk that is already going.
        // lazy because the init is nonisolated, so Compositor can build this off
        // the main actor, and these closures capture self.
        //
        // scaled progress with drift: a series takes about as long as its slowest
        // origin, so a stretch with nothing finishing is silence the system reads
        // as a stall. the bar is a liveness signal and the subtitle is the
        // measure, which is why they tell slightly different stories
        @ObservationIgnored private lazy var task = ContinuedTask(
            identifier: Constants.Tasks.refresh,
            log: log,
            tick: { [weak self] in
                guard let self, self.isRunning, self.total > 0 else { return nil }
                let scale = Int64(self.total) * Limits.scale
                return ContinuedTask.Tick(
                    done: min(Int64(self.completed) * Limits.scale + self.drift.values.reduce(0, +), scale),
                    total: scale,
                    subtitle: "\(self.completed) of \(self.total)"
                )
            },
            // asymptotic on purpose: a fixed step reaches the ceiling and stops,
            // which brings the silence back later rather than removing it.
            // approaching a ceiling it never reaches means a series that is
            // genuinely stuck still reports movement
            drift: { [weak self] in
                guard let self else { return }
                for id in self.active {
                    let current = self.drift[id] ?? 0
                    self.drift[id] = current + (Limits.ceiling - current) / 4
                }
            }
        )
        // new chapters this run found, for the one notification it may post
        @ObservationIgnored private var added = 0
        @ObservationIgnored private var touched = 0
        @ObservationIgnored private var automatic = false
        @ObservationIgnored private var pending: [Series] = []
        // how far each in-flight series has drifted, 0..<ceiling
        @ObservationIgnored private var drift: [Int64: Int64] = [:]

        var isRunning: Bool { run != nil }

        private enum Limits {
            // series at a time. politeness is the host gate's job - this is pace,
            // and six across four hosts keeps every host inside its own budget
            static let width = 6

            // units per series. large enough that a quarter of the remaining gap
            // is still a whole number after many ticks
            static let scale: Int64 = 1000

            // where a series in flight drifts to but never arrives, so finishing
            // it is still a visible jump rather than a rounding error
            static let ceiling: Int64 = 900
        }

        // nonisolated so Compositor can build it: that init opens the database
        // and runs migrations, so it cannot be on the main actor. legal because
        // this only assigns empty values
        nonisolated init(
            database: DatabaseClient,
            registry: Registry,
            log: AppLog = .shared
        ) {
            self.database = database
            self.registry = registry
            self.worker = OriginRefresher(database: database, log: log)
            self.log = log
        }

        // MARK: One origin

        func chapters(
            source: Source,
            seriesSlug: String,
            originId: OriginRecord.ID
        ) async -> OriginRefresher.Outcome {
            mark(originId.rawValue, by: 1)
            defer { mark(originId.rawValue, by: -1) }

            return await worker.chapters(source: source, seriesSlug: seriesSlug, originId: originId)
        }

        func join(originId: OriginRecord.ID) async -> OriginRefresher.Outcome? {
            mark(originId.rawValue, by: 1)
            defer { mark(originId.rawValue, by: -1) }

            return await worker.join(originId: originId)
        }

        private func mark(_ origin: Int64, by delta: Int) {
            let count = (fetching[origin] ?? 0) + delta
            fetching[origin] = count > 0 ? count : nil
        }

        func metadata(source: Source, seriesSlug: String, originId: OriginRecord.ID) async {
            await worker.metadata(source: source, seriesSlug: seriesSlug, originId: originId)
        }

        // MARK: The library walk

        func start(
            collection: CollectionRecord.ID? = nil,
            named name: String? = nil,
            automatic: Bool = false
        ) {
            guard run == nil else { return }
            self.automatic = automatic

            let sort = LibrarySort(
                rawValue: UserDefaults.standard.string(forKey: Preferences.Key.librarySort) ?? ""
            ) ?? Preferences.Default.librarySort
            let ascending = UserDefaults.standard.object(forKey: Preferences.Key.librarySortAscending) as? Bool
                ?? Preferences.Default.librarySortAscending

            scope = name
            current = nil
            completed = 0
            total = 0
            failures = 0
            added = 0
            touched = 0

            // the work starts here, not in the launch handler. apple's own
            // guidance, and the shipped counterexample is instructive: aidoku
            // hangs its refresh off the handler, so a submission that fails
            // device-specifically turns into a refresh that silently never runs
            run = Task { [weak self] in
                await self?.walk(collection: collection, sort: sort, ascending: ascending)
                await self?.report()
                self?.finish()
            }

            // an automatic run is already inside a system task with its own
            // runtime; asking for a second one on top of it is not what the
            // continued-processing api is for
            if !automatic { submit(named: name) }
        }

        func cancel() {
            guard isRunning else { return }
            log.log("run cancelled at \(completed) of \(total)", category: "refresh")
            run?.cancel()
            Task { [worker] in await worker.cancelAll() }
        }

        private func finish() {
            stamp()
            drift = [:]
            run = nil
            pending = []
            active = []
            queued = []
            current = nil
            scope = nil
            total = 0

            task.finish()
        }

        // one notification, only for a run nobody watched, only when it found
        // something. a run you can see is already telling that story, and
        // "nothing new" stays silent
        private func report() async {
            guard added > 0, UIApplication.shared.applicationState != .active else { return }
            await Notifier.newChapters(added, series: touched)
        }

        private func walk(collection: CollectionRecord.ID?, sort: LibrarySort, ascending: Bool) async {
            let work: [Series]
            do {
                work = try await database.reader.read { [registry] db in
                    try Self.work(collection: collection, sort: sort, ascending: ascending, registry: registry, in: db)
                }
            } catch {
                log.log("library refresh could not build its work list - \(error)", category: "refresh")
                return
            }

            guard !work.isEmpty else { return }
            total = work.count
            queued = Set(work.map(\.id))
            log.log("library refresh walking \(work.count) series", category: "refresh")

            // a fixed width rather than one task per series: two hundred tasks
            // all parked at the host gate is the same wall clock and a far worse
            // thing to cancel
            await withTaskGroup(of: Completion.self) { group in
                // an array rather than an iterator, because something else can
                // refresh a series while it sits here waiting - and then the
                // walk must not fetch it a second time
                pending = work

                for _ in 0..<min(Limits.width, work.count) {
                    guard let series = take() else { break }
                    dispatch(series)
                    group.addTask { [worker] in await Self.check(series, with: worker) }
                }

                while let result = await group.next() {
                    active.remove(result.id)
                    drift[result.id] = nil
                    completed += 1
                    failures += result.failures
                    added += result.added
                    if result.added > 0 { touched += 1 }
                    advance()

                    guard !Task.isCancelled else { continue }

                    if let series = take() {
                        dispatch(series)
                        group.addTask { [worker] in await Self.check(series, with: worker) }
                    }
                }
            }
        }

        private func take() -> Series? {
            pending.isEmpty ? nil : pending.removeFirst()
        }

        // somebody refreshed this series themselves while it waited its turn -
        // pulling to refresh means "check this one now", and the fastest way to
        // honour that is to let it happen rather than reorder a queue. the walk
        // drops it instead, because it is already done: counting it as completed
        // is truthful, it was checked, just not by us
        func dequeue(series id: Int64) {
            guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
            pending.remove(at: index)
            queued.remove(id)
            completed += 1
            advance()
            log.log("series \(id) refreshed elsewhere - dropped from the walk", category: "refresh")
        }

        // a series leaves the queue exactly when it starts, so the two sets are
        // never both true for it and a screen can ask either question
        private func dispatch(_ series: Series) {
            queued.remove(series.id)
            active.insert(series.id)
            drift[series.id] = 0
            current = series.title
            advance()
        }

        // MARK: The schedule

        // two stamps, not one. the visible fact is "when was the library last
        // checked" and it moves for any run; the scheduling anchor moves only
        // for an automatic one, so pulling to refresh never postpones the next
        // automatic check. suwayomi keeps exactly this pair, and the reason is
        // that conflating them makes an active user's schedule drift forever
        private func stamp() {
            let defaults = UserDefaults.standard
            defaults.set(Date.now, forKey: Preferences.Key.refreshedDate)
            if automatic { defaults.set(Date.now, forKey: Preferences.Key.refreshedAutomaticallyDate) }
            automatic = false

            schedule()
        }

        // re-armed at the end of every run and at launch, never only on
        // backgrounding: suwatte submits solely from its scene-phase hook and
        // its handler never re-submits, so its scheduling can stop for good
        func schedule() {
            let hours = UserDefaults.standard.integer(forKey: Preferences.Key.refreshInterval)

            #if !targetEnvironment(simulator)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Constants.Tasks.scheduledRefresh)
            guard hours > 0 else { return }

            let request = BGProcessingTaskRequest(identifier: Constants.Tasks.scheduledRefresh)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = anchor.addingTimeInterval(TimeInterval(hours) * 3600)

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                log.log("scheduled refresh not accepted - \(error)", category: "refresh")
            }
            #endif
        }

        // the system may simply never run the task - background app refresh off,
        // low power mode, a force quit, or its own judgement - and it tells us
        // nothing in any of those cases. so the interval is also checked when
        // the app is opened, which is the half nobody can switch off
        func catchUp() {
            let defaults = UserDefaults.standard
            let hours = defaults.integer(forKey: Preferences.Key.refreshInterval)
            guard hours > 0, !isRunning else { return }

            guard let last = defaults.object(forKey: Preferences.Key.refreshedAutomaticallyDate) as? Date else {
                // a first-ever launch stamps and waits rather than walking a
                // library that was only just added
                defaults.set(Date.now, forKey: Preferences.Key.refreshedAutomaticallyDate)
                schedule()
                return
            }

            let due = last.addingTimeInterval(TimeInterval(hours) * 3600)
            guard Date.now >= due else { return }

            // one run, not one per interval missed. how many were skipped is not
            // a thing anybody needs made up for
            log.log("automatic refresh was due \(due.formatted()) - running now", category: "refresh")
            start(automatic: true)
        }

        private var anchor: Date {
            UserDefaults.standard.object(forKey: Preferences.Key.refreshedAutomaticallyDate) as? Date ?? .now
        }

        // MARK: The background task

        // registered before the end of launch, which the api requires - and from
        // a launch the system started itself, so this has to run whether or not
        // a screen ever appears
        func register() {
            task.register { [weak self] in self?.cancel() }

            #if !targetEnvironment(simulator)
            // the scheduled half is a different api on purpose: opportunistic,
            // no ui, minutes of runtime rather than an extension of something
            // the user is watching
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Constants.Tasks.scheduledRefresh,
                using: nil
            ) { task in
                Task { @MainActor [weak self] in
                    guard let self else { return task.setTaskCompleted(success: false) }

                    task.expirationHandler = { Task { @MainActor in self.cancel() } }
                    self.start(automatic: true)

                    // the run owns its own completion, so this waits on it
                    // rather than returning and letting the system reclaim the
                    // process mid-walk
                    while self.isRunning {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    task.setTaskCompleted(success: true)
                }
            }
            #endif
        }

        private func submit(named name: String?) {
            task.submit(
                title: name.map { "Updating \($0)" } ?? "Updating Library",
                subtitle: "Checking for new chapters"
            )
        }

        private func advance() {
            task.advance()
        }

        // every origin of a series at once, exactly as the Details screen does.
        // nonisolated: the walk must not run on the main actor, only the numbers
        // it reports live there
        nonisolated private static func check(_ series: Series, with worker: OriginRefresher) async -> Completion {
            await withTaskGroup(of: OriginRefresher.Outcome.self) { group in
                for origin in series.origins {
                    group.addTask {
                        await worker.chapters(
                            source: origin.source,
                            seriesSlug: origin.slug,
                            originId: origin.id
                        )
                    }
                }

                var failures = 0
                var added = 0
                for await outcome in group {
                    if case .failed = outcome { failures += 1 }
                    added += outcome.count
                }
                return Completion(id: series.id, failures: failures, added: added)
            }
        }

        private struct Completion: Sendable {
            let id: Int64
            let failures: Int
            let added: Int
        }
    }
}

// MARK: - The work list

extension Compositor.Refresh {
    fileprivate struct Series: Sendable {
        let id: Int64
        let title: String
        let origins: [Origin]
    }

    fileprivate struct Origin: Sendable {
        let id: OriginRecord.ID
        let slug: String
        let source: Source
    }

    private struct Row: Decodable, FetchableRecord {
        let seriesId: Int64
        let title: String
        let originId: Int64
        let originSlug: String
        let sourceSlug: String
    }

    // ordered the way the library the user is looking at is ordered, then
    // grouped in swift - the order has to survive the grouping, so this walks
    // the rows rather than using Dictionary(grouping:)
    nonisolated fileprivate static func work(
        collection: CollectionRecord.ID?,
        sort: LibrarySort,
        ascending: Bool,
        registry: Compositor.Registry,
        in db: Database
    ) throws -> [Series] {
        let ordering = "e.\(column(for: sort)) \(ascending ? "ASC" : "DESC")"
        let skips = Skips.stored.clauses
        let scope = collection == nil ? "" : """
            AND EXISTS(
                SELECT 1 FROM \(SeriesCollectionRecord.databaseTableName) sc
                WHERE sc.\(SeriesCollectionRecord.Columns.seriesId.name) = e.\(EntryView.Columns.seriesId.name)
                  AND sc.\(SeriesCollectionRecord.Columns.collectionId.name) = ?
            )
            """

        let sql = """
            SELECT
                e.\(EntryView.Columns.seriesId.name) AS seriesId,
                e.\(EntryView.Columns.title.name) AS title,
                o.id AS originId,
                o.\(OriginRecord.Columns.slug.name) AS originSlug,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(EntryView.databaseTableName) e
            JOIN \(OriginRecord.databaseTableName) o
              ON o.\(OriginRecord.Columns.seriesId.name) = e.\(EntryView.Columns.seriesId.name)
            JOIN \(SourceRecord.databaseTableName) src
              ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE e.\(EntryView.Columns.inLibrary.name) = 1
              AND src.\(SourceRecord.Columns.installed.name) = 1
              AND src.\(SourceRecord.Columns.disabled.name) = 0
              \(scope)
              \(skips)
            ORDER BY \(ordering), e.\(EntryView.Columns.seriesId.name) ASC,
                     o.\(OriginRecord.Columns.priority.name) ASC, o.id ASC
            """

        let rows = try Row.fetchAll(
            db,
            sql: sql,
            arguments: collection.map { StatementArguments([$0.rawValue]) } ?? StatementArguments()
        )

        var series: [Series] = []
        var currentId: Int64?
        var currentTitle = ""
        var origins: [Origin] = []

        func flush() {
            guard let id = currentId, !origins.isEmpty else { return }
            series.append(Series(id: id, title: currentTitle, origins: origins))
        }

        for row in rows {
            if row.seriesId != currentId {
                flush()
                currentId = row.seriesId
                currentTitle = row.title
                origins = []
            }

            // a source row can outlive the code that reads it, and an origin
            // nothing can open is not work
            guard let source = registry.source(slug: row.sourceSlug) else { continue }
            origins.append(
                Origin(id: OriginRecord.ID(rawValue: row.originId), slug: row.originSlug, source: source)
            )
        }
        flush()

        return series
    }

    // what the walk is allowed to leave alone. read once when a run starts
    // rather than per row, and expressed as sql so a skipped series never
    // becomes work in the first place
    struct Skips: Sendable {
        var completed = false
        var unread = false
        var notStarted = false

        static var stored: Skips {
            let defaults = UserDefaults.standard
            return Skips(
                completed: defaults.bool(forKey: Preferences.Key.refreshSkipCompleted),
                unread: defaults.bool(forKey: Preferences.Key.refreshSkipUnread),
                notStarted: defaults.bool(forKey: Preferences.Key.refreshSkipNotStarted)
            )
        }

        var clauses: String {
            var parts: [String] = []

            // the provider's status, not the reader's. it only moves when the
            // series is opened, since the bulk walk fetches chapters and not
            // metadata - a series that finished stays "ongoing" here until
            // visited, which is the honest cost of the cheaper walk
            if completed {
                parts.append("AND e.\(EntryView.Columns.publication.name) != '\(Publication.Completed.rawValue)'")
            }

            // already behind on this one - checking for more is not what the
            // reader is short of
            if unread {
                parts.append("AND e.\(EntryView.Columns.unreadCount.name) = 0")
            }

            // never opened. the sentinel is distantPast rather than null, so
            // "started" is a comparison and not an IS NOT NULL
            if notStarted {
                parts.append("AND e.\(EntryView.Columns.lastReadDate.name) > '1970-01-01 00:00:00.000'")
            }

            return parts.joined(separator: "\n              ")
        }
    }

    // exhaustive on purpose: a new sort option should not compile until the walk
    // knows how to order by it
    nonisolated private static func column(for sort: LibrarySort) -> String {
        switch sort {
        case .added: EntryView.Columns.addedDate.name
        case .updated: EntryView.Columns.updatedDate.name
        case .lastRead: EntryView.Columns.lastReadDate.name
        case .unread: EntryView.Columns.unreadCount.name
        case .title: EntryView.Columns.title.name
        }
    }
}

// MARK: - The worker

// one origin, checked once, and the only thing that writes chapter rows. an
// actor because it holds which origins are in flight: a screen refreshing a
// series the library walk is already touching is ordinary, and one place that
// knows beats every caller deciding for itself. CoverDownloader is the same
// shape - the work is owned here, not by whoever asked for it
actor OriginRefresher {
    private let database: DatabaseClient
    private let log: AppLog
    private var inFlight: [OriginRecord.ID: Task<Outcome, Never>] = [:]

    init(database: DatabaseClient, log: AppLog = .shared) {
        self.database = database
        self.log = log
    }

    enum Outcome: Equatable, Sendable {
        case added(Int)
        case unchanged
        case failed(String)
        // the run was stopped, which is the user's decision rather than the
        // source misbehaving - kept distinct so it is never recorded as a
        // failure, counted as one, or shown as one
        case cancelled

        var count: Int {
            if case let .added(count) = self { count } else { 0 }
        }
    }

    // a second caller for an origin already in flight joins it rather than
    // skipping: you pulled to refresh and are owed the real answer, not
    // "someone else has it". one request, both callers get its result
    func chapters(
        source: Source,
        seriesSlug: String,
        originId: OriginRecord.ID
    ) async -> Outcome {
        if let existing = inFlight[originId] {
            return await existing.value
        }

        // registered before the first suspension. an actor releases between
        // awaits, so a check-then-await-then-insert would let two callers both
        // find nothing and both fetch
        let task = Task { [weak self] in
            guard let self else { return Outcome.failed("Refresh was cancelled.") }
            let outcome = await self.perform(source: source, seriesSlug: seriesSlug, originId: originId)
            await self.finish(originId)
            return outcome
        }
        inFlight[originId] = task

        return await task.value
    }

    // metadata is a separate half so a library walk can skip it. a failure here
    // never blocks chapters - they are what a refresh is reaching for, and the
    // screen keeps what it has rather than nagging
    func metadata(source: Source, seriesSlug: String, originId: OriginRecord.ID) async {
        do {
            let detail = try await source.details(seriesSlug: seriesSlug)
            try await database.writer.write { db in
                try Self.write(detail, for: originId, in: db)
            }
        } catch {
            log.log("origin \(originId.rawValue) metadata refresh failed - \(error)", category: "refresh")
        }
    }

    // attach to a fetch already running and take its answer, or nil if there is
    // nothing to attach to. distinct from chapters(_:) on purpose: that starts
    // one when none exists, which is the opposite of what a screen reopened
    // mid-fetch wants. the check and the await are one actor step, so an origin
    // finishing in between cannot turn this into a second request
    func join(originId: OriginRecord.ID) async -> Outcome? {
        guard let existing = inFlight[originId] else { return nil }
        return await existing.value
    }

    // cancelled explicitly, because the fetch is unstructured: a caller walking
    // away must not kill a fetch another is still awaiting
    func cancel(originId: OriginRecord.ID) {
        inFlight[originId]?.cancel()
    }

    func cancelAll() {
        for task in inFlight.values { task.cancel() }
    }

    private func finish(_ originId: OriginRecord.ID) {
        inFlight[originId] = nil
    }

    private func perform(
        source: Source,
        seriesSlug: String,
        originId: OriginRecord.ID
    ) async -> Outcome {
        do {
            let stored = try await database.reader.read { db in
                try ChapterRecord
                    .filter(ChapterRecord.Columns.originId == originId.rawValue)
                    .fetchCount(db)
            }

            // a source that can say cheaply whether anything moved is asked that
            // instead. everyone else is asked for the list, which is the whole of
            // the base contract
            let listing: ChapterRevalidation
            if let revalidating = source as? any RevalidatingSource {
                listing = try await revalidating.chapters(seriesSlug: seriesSlug, stored: stored)
            } else {
                listing = .changed(try await source.chapters(seriesSlug: seriesSlug))
            }
            let fetched = Date.now

            let added = try await database.writer.write { db -> Int in
                var inserted = 0
                if case let .changed(entries) = listing, !entries.isEmpty {
                    inserted = try Self.upsert(entries, for: originId, in: db)
                }

                // the source answered either way, so the date is stamped either
                // way - only a throw leaves the stored list unknown
                _ = try OriginRecord
                    .filter(key: originId.rawValue)
                    .updateAll(
                        db,
                        OriginRecord.Columns.chaptersFetchedDate.set(to: fetched),
                        OriginRecord.Columns.fetchAttemptedDate.set(to: fetched),
                        OriginRecord.Columns.fetchError.set(to: nil)
                    )

                // insert-or-ignore, so this only ever heals a series created
                // before seeding existed - a saved order is never touched
                if let origin = try OriginRecord.fetchOne(db, key: originId.rawValue) {
                    try SeriesLanguagePriorityRecord.seedDefaults(for: origin.seriesId, in: db)
                }

                return inserted
            }

            log.log(
                "origin \(originId.rawValue) \(listing.summary), \(added) new, had \(stored)",
                category: "refresh"
            )

            return added > 0 ? .added(added) : .unchanged
        } catch is CancellationError {
            // nothing is stamped: the origin was not asked and did not answer,
            // so its dates and its error column both stay as they were. not
            // logged either - cancelling produces one of these per origin in
            // flight, and the run-level line already says it happened
            return .cancelled
        } catch NetworkError.cancelled {
            return .cancelled
        } catch {
            let failure = Failure(error, fallback: "Couldn't Load Chapters")
            let reason = failure.message.isEmpty ? failure.title : failure.message

            // the row outlives the run: the source keeps saying it is failing
            // until an attempt succeeds, which is why this is a column rather
            // than a variable
            try? await database.writer.write { db in
                _ = try OriginRecord
                    .filter(key: originId.rawValue)
                    .updateAll(
                        db,
                        OriginRecord.Columns.fetchAttemptedDate.set(to: Date.now),
                        OriginRecord.Columns.fetchError.set(to: reason)
                    )
            }

            log.log("origin \(originId.rawValue) chapter fetch FAILED - \(error)", category: "refresh")
            return .failed(reason)
        }
    }
}

// MARK: - Writes

extension OriginRefresher {
    // metadata a refresh is allowed to overwrite. titles and covers are add-only,
    // so a pick the user made can never be taken away by a later fetch
    nonisolated fileprivate static func write(
        _ detail: SeriesDetail,
        for originId: OriginRecord.ID,
        in db: Database
    ) throws {
        guard var origin = try OriginRecord.fetchOne(db, key: originId.rawValue) else { return }

        _ = try origin.updateChanges(db) {
            $0.synopsis = detail.synopsis
            $0.classification = detail.classification
            $0.publication = detail.publication
            $0.metadataFetchedDate = .now
        }

        for value in [detail.title] + detail.altTitles {
            _ = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: origin.seriesId, originId: originId, value: value),
                in: db
            )
        }

        for url in detail.covers {
            _ = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: origin.seriesId, originId: originId, url: url, path: nil),
                in: db
            )
        }
    }

    // chapters arrive independently of the rest of a series, so this runs on its
    // own and is safe to repeat. progress, lastReadDate and addedDate are never
    // overwritten - the update path lists the fields it touches, and none of
    // those are among them, so a row keeps its progress and the day it arrived
    @discardableResult
    nonisolated fileprivate static func upsert(
        _ entries: [ChapterEntry],
        for originId: OriginRecord.ID,
        in db: Database
    ) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        var inserted = 0

        var scanlators: [String: ScanlatorRecord.ID] = [:]
        for entry in entries where scanlators[entry.scanlator] == nil {
            let scanlator = try ScanlatorRecord.findOrCreate(
                ScanlatorRecord(id: nil, name: entry.scanlator),
                in: db
            )
            guard let scanlatorId = scanlator.id else { continue }
            scanlators[entry.scanlator] = scanlatorId

            // order of first appearance, and only when absent - a refresh must not
            // discard an ordering the user has since set
            var priority = OriginScanlatorPriorityRecord(
                originId: originId,
                scanlatorId: scanlatorId,
                priority: scanlators.count - 1
            )
            try priority.insert(db, onConflict: .ignore)
        }

        let existing = try ChapterRecord
            .filter(ChapterRecord.Columns.originId == originId)
            .fetchAll(db)
        let bySlug = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in entries {
            guard let scanlatorId = scanlators[entry.scanlator] else { continue }

            if var current = bySlug[entry.slug] {
                // diffed against the stored encoding, so a source that returned
                // nothing new issues no UPDATE and wakes no observation
                _ = try current.updateChanges(db) {
                    $0.title = entry.title
                    $0.number = entry.number
                    $0.publishedDate = entry.publishedDate
                    $0.language = entry.language
                    $0.url = entry.url
                }
            } else {
                var chapter = ChapterRecord(
                    id: nil,
                    originId: originId,
                    scanlatorId: scanlatorId,
                    slug: entry.slug,
                    title: entry.title,
                    number: entry.number,
                    publishedDate: entry.publishedDate,
                    language: entry.language,
                    progress: 0,
                    lastReadDate: nil,
                    url: entry.url,
                    path: nil
                )
                try chapter.insert(db)
                inserted += 1
            }
        }

        return inserted
    }
}

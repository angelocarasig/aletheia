//
//  Compositor+Refresh.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import BackgroundTasks
import Foundation
import GRDB
import Observation
import Tagged
import UIKit

extension Compositor {
    // both a single-origin check and the library walk go through the same
    // worker below - v2 kept two copies of that and they had drifted within a
    // year. see docs/features/background-activity.md 6.4
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
        // fully excluded, not per-origin - a series with one skipped origin and
        // one checked origin still got refreshed, so it doesn't belong here
        private(set) var skipped = 0

        private(set) var active: Set<Int64> = []
        private(set) var queued: Set<Int64> = []

        // counted rather than a set: two callers can join one fetch, and the
        // first to return must not clear a mark the second is still standing behind
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

        // the run does not wait for this and does not need it - it only extends a
        // walk already going. lazy since these closures capture self, which the
        // nonisolated init cannot
        //
        // a series takes about as long as its slowest origin, so a stretch with
        // nothing finishing reads as a stall. the bar is a liveness signal and
        // the subtitle is the measure, which is why they tell slightly different stories
        @ObservationIgnored private lazy var task = ContinuedTask(
            identifier: Constants.Tasks.refresh,
            log: log,
            tick: { [weak self] in
                guard let self, self.isRunning, self.total > 0 else { return nil }
                let scale = Int64(self.total) * Limits.scale
                return ContinuedTask.Tick(
                    done: min(
                        Int64(self.completed) * Limits.scale + self.drift.values.reduce(0, +), scale
                    ),
                    total: scale,
                    subtitle: "\(self.completed) of \(self.total)"
                )
            },
            // asymptotic on purpose - a fixed step reaches the ceiling and stops,
            // bringing the silence back later. approaching a ceiling it never
            // reaches means a genuinely stuck series still reports movement
            drift: { [weak self] in
                guard let self else { return }
                for id in self.active {
                    let current = self.drift[id] ?? 0
                    self.drift[id] = current + (Limits.ceiling - current) / 4
                }
            }
        )
        @ObservationIgnored private var added = 0
        @ObservationIgnored private var touched = 0
        @ObservationIgnored private var automatic = false
        // a run inside a system task leaves re-arming to the launch handler, which
        // only re-arms once that task completes. a foreground automatic run
        // (catchUp noticing a missed interval) is not hosted and re-arms as
        // usual - that's why this is a separate flag from `automatic`
        @ObservationIgnored private var hosted = false
        @ObservationIgnored private var pending: [Series] = []
        @ObservationIgnored private var drift: [Int64: Int64] = [:]

        var isRunning: Bool { run != nil }

        private enum Limits {
            // politeness is the host gate's job, this is pace - six across four
            // hosts keeps every host inside its own budget
            static let width = 6

            // large enough that a quarter of the remaining drift gap is still a
            // whole number after many ticks
            static let scale: Int64 = 1000

            // where a series in flight drifts to but never arrives, so finishing
            // is still a visible jump rather than a rounding error
            static let ceiling: Int64 = 900
        }

        // nonisolated so Compositor can build this off the main actor - legal
        // since this only assigns empty values
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

        func metadata(source: Source, seriesSlug: String, originId: OriginRecord.ID) async
            -> MetadataOutcome
        {
            await worker.metadata(source: source, seriesSlug: seriesSlug, originId: originId)
        }

        // MARK: The library walk

        // series nil is the whole library; a non-nil (possibly empty) set scopes
        // the walk to exactly those - the caller resolves what "this section" or
        // "this collection" means before calling in, so this stays a plain id set
        func start(
            series: Set<SeriesRecord.ID>? = nil,
            named name: String? = nil,
            automatic: Bool = false
        ) {
            guard run == nil else { return }
            self.automatic = automatic

            let order: Order
            if automatic {
                order = .rotation
            } else {
                let sort =
                    LibrarySort(
                        rawValue: UserDefaults.standard.string(forKey: Preferences.Key.librarySort)
                            ?? ""
                    ) ?? Preferences.Default.librarySort
                let ascending =
                    UserDefaults.standard.object(forKey: Preferences.Key.librarySortAscending)
                    as? Bool
                    ?? Preferences.Default.librarySortAscending
                order = .library(sort, ascending: ascending)
            }

            scope = name
            current = nil
            completed = 0
            total = 0
            failures = 0
            skipped = 0
            added = 0
            touched = 0

            // the work starts here, not in the launch handler - aidoku hangs its
            // refresh off the handler instead, so a submission that fails
            // device-specifically turns into a refresh that silently never runs
            run = Task { [weak self] in
                await self?.walk(series: series, order: order)

                // cancelling a Task does not skip the rest of this closure - the
                // walk just returns early - so this check has to be explicit, or a
                // stopped run reports "no new chapters" for series nobody checked
                if !Task.isCancelled { await self?.report() }

                self?.finish()
            }

            // an automatic run is already inside a system task with its own
            // runtime - a second submission is not what the continued-processing
            // api is for
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

        private func report() async {
            guard UIApplication.shared.applicationState != .active else { return }

            // an empty manual run needs no telling - you asked for it and watched
            // it start; an empty automatic run still gets one, since it's the
            // only thing that ever says the automatic half is alive
            guard added > 0 || automatic else { return }

            await Notifier.refreshed(
                added: added,
                series: touched,
                checked: completed,
                failures: failures,
                skipped: skipped
            )
        }

        private func walk(series: Set<SeriesRecord.ID>?, order: Order) async {
            let work: [Series]
            do {
                let result = try await database.reader.read { [registry] db in
                    try Self.work(series: series, order: order, registry: registry, in: db)
                }
                work = result.series
                skipped = result.skipped
            } catch {
                log.log(
                    "library refresh could not build its work list - \(error)", level: .error,
                    category: "refresh")
                return
            }

            guard !work.isEmpty else { return }
            total = work.count
            queued = Set(work.map(\.id))
            log.log("library refresh walking \(work.count) series", category: "refresh")

            // a fixed width rather than one task per series - two hundred tasks
            // all parked at the host gate is the same wall clock and a far worse
            // thing to cancel
            await withTaskGroup(of: Completion.self) { group in
                // an array, not an iterator - something else can refresh a series
                // while it sits here waiting, and the walk must not fetch it twice
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
        // the walk drops it and counts it as completed, which is truthful: it
        // was checked, just not by us
        func dequeue(series id: Int64) {
            guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
            pending.remove(at: index)
            queued.remove(id)
            completed += 1
            advance()
            log.log("series \(id) refreshed elsewhere - dropped from the walk", category: "refresh")
        }

        private func dispatch(_ series: Series) {
            queued.remove(series.id)
            active.insert(series.id)
            drift[series.id] = 0
            current = series.title
            advance()
        }

        // MARK: The schedule

        // two stamps, not one: "when was the library last checked" moves for any
        // run, but the scheduling anchor moves only for an automatic one, so
        // pulling to refresh never postpones the next automatic check.
        // conflating them (as suwayomi does not) makes an active user's schedule drift forever
        private func stamp() {
            let defaults = UserDefaults.standard
            defaults.set(Date.now, forKey: Preferences.Key.refreshedDate)
            if automatic {
                defaults.set(Date.now, forKey: Preferences.Key.refreshedAutomaticallyDate)
            }
            automatic = false

            if !hosted { schedule() }
        }

        // re-armed at the end of every run and at launch, never only on
        // backgrounding - suwatte submits solely from its scene-phase hook, so its
        // scheduling can stop for good if that hook is ever missed
        func schedule(asap: Bool = false) {
            let automatic = UserDefaults.standard.bool(forKey: Preferences.Key.refreshAutomatic)

            #if targetEnvironment(simulator)
                log.log(
                    "scheduled refresh skipped - the simulator never accepts one",
                    category: "refresh")
            #else
                BGTaskScheduler.shared.cancel(
                    taskRequestWithIdentifier: Constants.Tasks.scheduledRefresh)
                guard automatic else {
                    log.log(
                        "scheduled refresh cancelled - automatic checks are off",
                        category: "refresh")
                    return
                }

                let request = BGProcessingTaskRequest(identifier: Constants.Tasks.scheduledRefresh)
                request.requiresNetworkConnectivity = true
                request.requiresExternalPower = false
                request.earliestBeginDate =
                    asap ? nil : anchor.addingTimeInterval(Constants.Refresh.automaticInterval)

                do {
                    try BGTaskScheduler.shared.submit(request)
                    log.log(
                        "scheduled refresh armed - \(request.earliestBeginDate.map { "no earlier than \($0.formatted())" } ?? "at the system's next opportunity")",
                        category: "refresh"
                    )
                } catch {
                    log.log("scheduled refresh not accepted - \(error)", category: "refresh")
                }
            #endif
        }

        // the system may simply never run the scheduled task, and tells us
        // nothing when it doesn't - so the interval is also checked on app open
        func catchUp() {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: Preferences.Key.refreshAutomatic), !isRunning else {
                return
            }

            guard
                let last = defaults.object(forKey: Preferences.Key.refreshedAutomaticallyDate)
                    as? Date
            else {
                defaults.set(Date.now, forKey: Preferences.Key.refreshedAutomaticallyDate)
                schedule()
                return
            }

            let due = last.addingTimeInterval(Constants.Refresh.automaticInterval)
            guard Date.now >= due else { return }

            log.log(
                "automatic refresh was due \(due.formatted()) - running now", category: "refresh")
            start(automatic: true)
        }

        private var anchor: Date {
            UserDefaults.standard.object(forKey: Preferences.Key.refreshedAutomaticallyDate)
                as? Date ?? .now
        }

        // MARK: The background task

        // only the continued-processing task - iOS 26 exempts it from having to
        // register before launch ends, so it stays with the owner that submits
        // it. the scheduled task is registered by Launch during launch itself,
        // since a system-started launch has no screens to reach this from
        func register() {
            task.register { [weak self] in self?.cancel() }
        }

        func adopt(_ task: BGTask) {
            task.expirationHandler = { Task { @MainActor [weak self] in self?.cancel() } }
            hosted = true
            start(automatic: true)

            Task { @MainActor [weak self] in
                guard let self else { return task.setTaskCompleted(success: false) }

                // waits on the run rather than returning early - the system can
                // reclaim the process mid-walk once this task reports done
                while self.isRunning {
                    try? await Task.sleep(for: .seconds(1))
                }

                // completed first, re-armed second - a request submitted while
                // this task is still open replaces the one the app was launched
                // to run, and the system may suspend us before setTaskCompleted,
                // leaving the task open with the next run scheduled by a process
                // that never said it had finished
                task.setTaskCompleted(success: true)
                self.hosted = false
                self.schedule()
            }
        }

        #if DEBUG
            // MARK: Rehearsal

            // nothing can make iOS decide to run a BGProcessingTask now - the api
            // offers no override - so this fakes the launch using the same
            // private hook the debugger uses. everything downstream is the real
            // path (handler, adopt, hosted flag, rotation, notification, re-arm);
            // only the system's choice of moment is fabricated.
            //
            // the five-second sleep below is not a race workaround - it is the
            // point of the exercise, putting the run after the screen is off,
            // which is where the real one lives. the background assertion buys
            // roughly thirty seconds, close to what a real run gets before an
            // unlock ends it, so a walk that does not finish here is representative, not broken
            func rehearse() async {
                guard !isRunning else { return }
                guard UserDefaults.standard.bool(forKey: Preferences.Key.refreshAutomatic) else {
                    log.log("rehearsal skipped - automatic checks are off", category: "refresh")
                    return
                }

                let app = UIApplication.shared
                var assertion = UIBackgroundTaskIdentifier.invalid

                // must be taken before the wait, or the process is suspended
                // during it and the wait never finishes
                assertion = app.beginBackgroundTask(withName: "refresh.rehearsal") {
                    guard assertion != .invalid else { return }
                    app.endBackgroundTask(assertion)
                    assertion = .invalid
                }

                // the assertion's budget is the harness's alone - a real scheduled
                // run gets minutes, not this - so a truncated rehearsal is this
                // number running out, not the feature failing
                let budget = app.backgroundTimeRemaining
                let allowance = budget > 1e6 ? "unbounded" : "\(Int(budget))s"
                // firing the hook consumes the pending request, so a second
                // rehearsal in a row finds nothing to launch without this
                schedule()

                log.log(
                    "rehearsal armed - firing in 5s, assertion allows \(allowance)",
                    category: "refresh")

                try? await Task.sleep(for: .seconds(5))

                let pending = await BGTaskScheduler.shared.pendingTaskRequests()
                guard pending.contains(where: { $0.identifier == Constants.Tasks.scheduledRefresh })
                else {
                    log.log(
                        "rehearsal - nothing pending to launch, is the interval set?",
                        level: .warning,
                        category: "refresh"
                    )
                    if assertion != .invalid { app.endBackgroundTask(assertion) }
                    return
                }

                let scheduler = BGTaskScheduler.shared
                let hook = NSSelectorFromString("_simulateLaunchForTaskWithIdentifier:")

                if scheduler.responds(to: hook) {
                    log.log("rehearsal firing a simulated launch", category: "refresh")
                    _ = scheduler.perform(hook, with: Constants.Tasks.scheduledRefresh)
                } else {
                    // hook is undocumented and may disappear in a future OS - falls
                    // back to exercising the walk directly, losing only the handler
                    log.log(
                        "rehearsal - no simulate hook, starting the walk directly", level: .warning,
                        category: "refresh")
                    start(automatic: true)
                }

                // the handler resolves the graph before starting anything, so the
                // run does not exist the instant the hook returns - checking for
                // the end before the beginning would see "not running", call it
                // finished, and drop the assertion while the real walk is still unprotected
                var settling = 0
                while !isRunning && settling < 100 {
                    try? await Task.sleep(for: .milliseconds(100))
                    settling += 1
                }

                guard isRunning else {
                    log.log(
                        "rehearsal - the launch never produced a run", level: .warning,
                        category: "refresh")
                    if assertion != .invalid { app.endBackgroundTask(assertion) }
                    return
                }

                log.log("rehearsal - run started, holding the assertion open", category: "refresh")

                // finish() clears `total` but not `completed`, so a tick landing
                // after the run ends would read "16 of 0" - `walked` holds the
                // last non-zero total instead. `completed` is read live rather
                // than snapshotted, which would just report the count from a
                // second before the end
                var elapsed = 0
                var walked = 0
                while isRunning {
                    if total > 0 { walked = total }

                    try? await Task.sleep(for: .seconds(1))
                    elapsed += 1

                    if elapsed % 10 == 0 {
                        // the origins, not `current` - with more than one in flight,
                        // `current` is as likely to name a bystander as the culprit
                        let stuck = await worker.outstanding()
                        log.log(
                            "rehearsal at \(elapsed)s - \(completed)/\(max(walked, total)) done, \(queued.count) queued, waiting on [\(stuck.joined(separator: ", "))]",
                            category: "refresh"
                        )
                    }

                    if elapsed >= 300 {
                        log.log(
                            "rehearsal giving up after 5m - cancelling", level: .warning,
                            category: "refresh")
                        cancel()
                        break
                    }
                }

                let left = app.backgroundTimeRemaining
                log.log(
                    "rehearsal over at \(completed) of \(walked) after \(elapsed)s, \(left > 1e6 ? "unbounded" : "\(Int(left))s") left",
                    category: "refresh"
                )

                if assertion != .invalid {
                    app.endBackgroundTask(assertion)
                    assertion = .invalid
                }
            }
        #endif

        private func submit(named name: String?) {
            task.submit(
                title: name.map { "Updating \($0)" } ?? "Updating Library",
                subtitle: "Checking for new chapters"
            )
        }

        private func advance() {
            task.advance()
        }

        // nonisolated - the walk must not run on the main actor, only the numbers
        // it reports live there
        nonisolated private static func check(_ series: Series, with worker: OriginRefresher) async
            -> Completion
        {
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

    // walks the rows rather than using Dictionary(grouping:) - the order has to
    // survive the grouping, and a dictionary does not preserve one
    nonisolated fileprivate static func work(
        series: Set<SeriesRecord.ID>?,
        order: Order,
        registry: Compositor.Registry,
        in db: Database
    ) throws -> (series: [Series], skipped: Int) {
        let ordering = order.clause
        let skips = Skips.stored

        // an explicit, possibly-empty id list rather than a collection lookup -
        // the caller (a section, a collection, "uncategorized") has already
        // resolved membership by the time this runs, so the walk itself no
        // longer needs to know what a collection is
        let scope: String
        let scopeArguments: StatementArguments
        if let series, !series.isEmpty {
            scope = """
                AND e.\(EntryView.Columns.seriesId.name)
                    IN (\(databaseQuestionMarks(count: series.count)))
                """
            scopeArguments = StatementArguments(series.map(\.rawValue))
        } else {
            scope = ""
            scopeArguments = StatementArguments()
        }

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
              \(skips.clauses)
            ORDER BY \(ordering), e.\(EntryView.Columns.seriesId.name) ASC,
                     o.\(OriginRecord.Columns.priority.name) ASC, o.id ASC
            """

        let rows = try Row.fetchAll(db, sql: sql, arguments: scopeArguments + skips.arguments)

        // same scope, no skip clauses - the gap between this and the post-skip
        // series count below is exactly the series the skip rules fully
        // excluded, not just thinned an origin off of
        let eligible =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(DISTINCT e.\(EntryView.Columns.seriesId.name))
                    FROM \(EntryView.databaseTableName) e
                    JOIN \(OriginRecord.databaseTableName) o
                      ON o.\(OriginRecord.Columns.seriesId.name) = e.\(EntryView.Columns.seriesId.name)
                    JOIN \(SourceRecord.databaseTableName) src
                      ON src.id = o.\(OriginRecord.Columns.sourceId.name)
                    WHERE e.\(EntryView.Columns.inLibrary.name) = 1
                      AND src.\(SourceRecord.Columns.installed.name) = 1
                      AND src.\(SourceRecord.Columns.disabled.name) = 0
                      \(scope)
                    """,
                arguments: scopeArguments
            ) ?? 0

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

            // a source row can outlive its registered implementation
            guard let source = registry.source(slug: row.sourceSlug) else { continue }
            origins.append(
                Origin(
                    id: OriginRecord.ID(rawValue: row.originId), slug: row.originSlug,
                    source: source)
            )
        }
        flush()

        return (series, max(0, eligible - series.count))
    }

    // an unwatched run goes least-recently-checked first, since it can be cut
    // short at any moment (the device unlocking is enough) - a stable order
    // would leave the tail of the library permanently unchecked, rotating
    // makes a short run cumulative instead
    enum Order: Sendable {
        case library(LibrarySort, ascending: Bool)
        case rotation

        var clause: String {
            switch self {
            case .library(let sort, let ascending):
                "e.\(column(for: sort)) \(ascending ? "ASC" : "DESC")"

            // MIN() per series, not per origin: a series skipped by preference
            // never moves its dates, so turning a skip off sorts it to the
            // front, which is the wanted answer for free
            case .rotation:
                """
                (SELECT MIN(o2.\(OriginRecord.Columns.fetchAttemptedDate.name))
                 FROM \(OriginRecord.databaseTableName) o2
                 WHERE o2.\(OriginRecord.Columns.seriesId.name) = e.\(EntryView.Columns.seriesId.name)) ASC
                """
            }
        }
    }

    struct Skips: Sendable {
        var completed = false
        var unread = false
        var notStarted = false
        var recentInterval = SkipRecentInterval.off

        static var stored: Skips {
            let defaults = UserDefaults.standard
            let recent =
                defaults.string(forKey: Preferences.Key.refreshSkipRecentInterval)
                .flatMap(SkipRecentInterval.init(rawValue:))
                ?? Preferences.Default.refreshSkipRecentInterval

            return Skips(
                completed: defaults.bool(forKey: Preferences.Key.refreshSkipCompleted),
                unread: defaults.bool(forKey: Preferences.Key.refreshSkipUnread),
                notStarted: defaults.bool(forKey: Preferences.Key.refreshSkipNotStarted),
                recentInterval: recent
            )
        }

        var clauses: String {
            var parts: [String] = []

            // either signal is enough to skip - AND-ing two NOT-equal clauses
            // means EITHER being complete excludes the row, not both. requiring
            // agreement would mean a reader who marked a series completed keeps
            // paying for it as long as the source stays vague about publication state
            if completed {
                parts.append(
                    "AND e.\(EntryView.Columns.status.name) != '\(Status.completed.rawValue)'")
                parts.append(
                    "AND e.\(EntryView.Columns.publication.name) != '\(Publication.Completed.rawValue)'"
                )
            }

            if unread {
                parts.append("AND e.\(EntryView.Columns.unreadCount.name) = 0")
            }

            // lastReadDate's sentinel is distantPast, not null - "started" is a
            // comparison, not an IS NOT NULL
            if notStarted {
                parts.append(
                    "AND e.\(EntryView.Columns.lastReadDate.name) > '1970-01-01 00:00:00.000'")
            }

            // per-origin, not per-series - chaptersFetchedDate lives on the
            // origin row this query already walks one at a time, and a
            // never-checked origin's sentinel (.distantPast) always sorts
            // before the cutoff, so it's never skipped by this
            if recentInterval.days != nil {
                parts.append("AND o.\(OriginRecord.Columns.chaptersFetchedDate.name) < ?")
            }

            return parts.joined(separator: "\n              ")
        }

        var arguments: StatementArguments {
            guard let days = recentInterval.days else { return StatementArguments() }
            return StatementArguments([Date.now.addingTimeInterval(-Double(days) * 86400)])
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

// actor because it tracks which origins are in flight - a screen refreshing a
// series the library walk already touches is ordinary, and needs one owner
// deciding rather than every caller. CoverDownloader is the same shape.
actor OriginRefresher {
    private let database: DatabaseClient
    private let log: AppLog
    private var inFlight: [OriginRecord.ID: Task<Outcome, Never>] = [:]
    private var started: [OriginRecord.ID: Date] = [:]

    init(database: DatabaseClient, log: AppLog = .shared) {
        self.database = database
        self.log = log
    }

    enum Outcome: Equatable, Sendable {
        case added(Int)
        case unchanged
        case failed(String)
        // kept distinct from .failed - a stopped run is the user's decision,
        // never a source misbehaving, and must not be recorded, counted, or shown as one
        case cancelled

        var count: Int {
            if case .added(let count) = self { count } else { 0 }
        }
    }

    func chapters(
        source: Source,
        seriesSlug: String,
        originId: OriginRecord.ID
    ) async -> Outcome {
        if let existing = inFlight[originId] {
            log.log(
                "origin \(originId.rawValue) already in flight, joining", level: .debug,
                category: "refresh")
            return await existing.value
        }

        // logged on start too, not just completion - an origin that never
        // appears otherwise could equally have never started or started and hung
        log.log(
            "origin \(originId.rawValue) (\(source.descriptor.slug)) starting", level: .debug,
            category: "refresh")
        started[originId] = Date.now

        // registered before the first suspension. an actor releases between
        // awaits, so a check-then-await-then-insert would let two callers both
        // find nothing and both fetch
        let task = Task { [weak self] in
            guard let self else { return Outcome.failed("Refresh was cancelled.") }
            let outcome = await self.perform(
                source: source, seriesSlug: seriesSlug, originId: originId)
            await self.finish(originId)
            return outcome
        }
        inFlight[originId] = task

        return await task.value
    }

    func outstanding() -> [String] {
        let now = Date.now
        return inFlight.keys
            .map { ($0, now.timeIntervalSince(started[$0] ?? now)) }
            .sorted { $0.1 > $1.1 }
            .map { "origin \($0.0.rawValue) (\(Int($0.1))s)" }
    }

    func metadata(source: Source, seriesSlug: String, originId: OriginRecord.ID) async
        -> MetadataOutcome
    {
        do {
            let detail = try await source.details(seriesSlug: seriesSlug)
            let changed = try await database.writer.write { db in
                try Self.write(detail, for: originId, source: source.descriptor.slug, in: db)
            }
            return changed ? .updated : .unchanged
        } catch is CancellationError {
            return .cancelled
        } catch NetworkError.cancelled {
            return .cancelled
        } catch {
            let failure = Failure(error, fallback: "Couldn't Refresh Metadata")
            let reason = failure.message.isEmpty ? failure.title : failure.message
            log.log(
                "origin \(originId.rawValue) metadata refresh failed - \(error)",
                level: .error,
                category: "refresh"
            )
            return .failed(reason)
        }
    }

    // the check and the await are one actor step, so an origin finishing in
    // between cannot turn this into a second request
    func join(originId: OriginRecord.ID) async -> Outcome? {
        guard let existing = inFlight[originId] else { return nil }
        return await existing.value
    }

    // explicit, since the fetch is unstructured - a caller walking away must
    // not kill a fetch another is still awaiting
    func cancel(originId: OriginRecord.ID) {
        inFlight[originId]?.cancel()
    }

    func cancelAll() {
        for task in inFlight.values { task.cancel() }
    }

    private func finish(_ originId: OriginRecord.ID) {
        inFlight[originId] = nil
        started[originId] = nil
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

            let listing: ChapterRevalidation
            if let revalidating = source as? any RevalidatingSource {
                listing = try await revalidating.chapters(seriesSlug: seriesSlug, stored: stored)
            } else {
                listing = .changed(try await source.chapters(seriesSlug: seriesSlug))
            }
            let fetched = Date.now

            let added = try await database.writer.write { db -> Int in
                var inserted = 0
                if case .changed(let entries) = listing, !entries.isEmpty {
                    inserted = try Self.upsert(entries, for: originId, in: db)
                }

                // stamped on any successful answer, changed or not - only a throw
                // leaves the stored list unknown
                _ =
                    try OriginRecord
                    .filter(key: originId.rawValue)
                    .updateAll(
                        db,
                        OriginRecord.Columns.chaptersFetchedDate.set(to: fetched),
                        OriginRecord.Columns.fetchAttemptedDate.set(to: fetched),
                        OriginRecord.Columns.fetchError.set(to: nil)
                    )

                // insert-or-ignore: only heals a series created before seeding
                // existed, never touches a saved order
                if let origin = try OriginRecord.fetchOne(db, key: originId.rawValue) {
                    try SeriesLanguagePriorityRecord.seedDefaults(for: origin.seriesId, in: db)

                    if inserted > 0 {
                        try Self.touchUpdatedDate(seriesId: origin.seriesId, in: db)
                    }
                }

                return inserted
            }

            log.log(
                "origin \(originId.rawValue) \(listing.summary), \(added) new, had \(stored)",
                level: .debug,
                category: "refresh"
            )

            return added > 0 ? .added(added) : .unchanged
        } catch is CancellationError {
            // not stamped and not logged - cancelling produces one of these per
            // origin in flight, and the run-level line already says it happened
            return .cancelled
        } catch NetworkError.cancelled {
            return .cancelled
        } catch {
            let failure = Failure(error, fallback: "Couldn't Load Chapters")
            let reason = failure.message.isEmpty ? failure.title : failure.message

            // a column, not a variable - the failure state outlives the run,
            // persisting until an attempt succeeds
            try? await database.writer.write { db in
                _ =
                    try OriginRecord
                    .filter(key: originId.rawValue)
                    .updateAll(
                        db,
                        OriginRecord.Columns.fetchAttemptedDate.set(to: Date.now),
                        OriginRecord.Columns.fetchError.set(to: reason)
                    )
            }

            log.log(
                "origin \(originId.rawValue) (\(source.descriptor.slug)) chapter fetch FAILED - \(error)",
                level: .error,
                category: "refresh"
            )
            return .failed(reason)
        }
    }
}

// MARK: - Writes

extension OriginRefresher {
    // titles and covers are add-only here - a pick the user made can never be
    // taken away by a later fetch. returns whether the core fields actually
    // changed, so a metadata-only refresh can tell "updated" from "unchanged"
    nonisolated fileprivate static func write(
        _ detail: SeriesDetail,
        for originId: OriginRecord.ID,
        source: String,
        in db: Database
    ) throws -> Bool {
        guard let origin = try OriginRecord.fetchOne(db, key: originId.rawValue) else {
            return false
        }

        var metadata = try MetadataRecord.adopt(
            seriesId: origin.seriesId,
            supplier: MetadataRecord.supplier(source: source, origin: origin.slug),
            originId: originId,
            in: db
        )

        let changed = try metadata.updateChanges(db) {
            $0.synopsis = detail.synopsis
            $0.classification = detail.classification
            $0.publication = detail.publication
            $0.fetchedDate = .now
        }

        guard let metadataId = metadata.id else { return changed }

        for value in [detail.title] + detail.altTitles {
            _ = try TitleRecord.findOrCreate(
                TitleRecord(
                    id: nil, seriesId: origin.seriesId, metadataId: metadataId, value: value),
                in: db
            )
        }

        for url in detail.covers {
            _ = try CoverRecord.findOrCreate(
                CoverRecord(
                    id: nil, seriesId: origin.seriesId, metadataId: metadataId, url: url, path: nil),
                in: db
            )
        }

        for name in detail.authors {
            try AuthorRecord.attach(name, to: origin.seriesId, in: db)
        }

        for name in detail.tags {
            try TagRecord.attach(name, to: origin.seriesId, in: db)
        }

        return changed
    }

    // progress, lastReadDate and addedDate are never overwritten - the update
    // path lists only the fields it touches, and none of those are among them
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

            // only when absent - a refresh must not discard an ordering the user has since set
            var priority = OriginScanlatorPriorityRecord(
                originId: originId,
                scanlatorId: scanlatorId,
                priority: scanlators.count - 1
            )
            try priority.insert(db, onConflict: .ignore)
        }

        let existing =
            try ChapterRecord
            .filter(ChapterRecord.Columns.originId == originId)
            .fetchAll(db)
        let bySlug = Dictionary(
            existing.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in entries {
            guard let scanlatorId = scanlators[entry.scanlator] else { continue }

            if var current = bySlug[entry.slug] {
                // diffed, so a source that returned nothing new issues no UPDATE
                // and wakes no observation
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

    // recomputes from scratch across every origin rather than taking the max of
    // old-vs-new - old-vs-new can't handle a republished date correcting one down
    @discardableResult
    nonisolated fileprivate static func touchUpdatedDate(
        seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> Bool {
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
        guard let latest else { return false }

        guard var series = try SeriesRecord.fetchOne(db, key: seriesId.rawValue) else {
            return false
        }
        return try series.updateChanges(db) {
            $0.updatedDate = latest
        }
    }
}

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
        // this run is inside a system task the launch handler still has to
        // complete, so it does not re-arm the schedule itself. a foreground
        // automatic run - catchUp noticing a missed interval - is not hosted and
        // re-arms as usual, which is why the flag is not just "automatic"
        @ObservationIgnored private var hosted = false
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

        func metadata(source: Source, seriesSlug: String, originId: OriginRecord.ID) async -> MetadataOutcome {
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

            let order: Order
            if automatic {
                order = .rotation
            } else {
                let sort = LibrarySort(
                    rawValue: UserDefaults.standard.string(forKey: Preferences.Key.librarySort) ?? ""
                ) ?? Preferences.Default.librarySort
                let ascending = UserDefaults.standard.object(forKey: Preferences.Key.librarySortAscending) as? Bool
                    ?? Preferences.Default.librarySortAscending
                order = .library(sort, ascending: ascending)
            }

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
                await self?.walk(collection: collection, order: order)

                // a run that was stopped has nothing to report: it did not check
                // the library, it got part way and was cut off, so "no new
                // chapters in 3 series" would be a claim about 197 series nobody
                // looked at. cancelling does not stop this closure - the walk
                // returns early and execution continues here - so the check has
                // to be explicit
                if !Task.isCancelled { await self?.report() }

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

        // one notification per run nobody watched, whether or not it found
        // anything. a reader following thirty ongoing series does not expect a
        // quiet day, so "nothing new" is a result rather than an absence - and
        // it is the only thing that ever says the automatic half is alive.
        // a run you can see is exempt: it is already telling that story
        private func report() async {
            guard UIApplication.shared.applicationState != .active else { return }

            // an empty manual run needs no telling - you asked for it, watched
            // it start, and the screen you came back to has the answer
            guard added > 0 || automatic else { return }

            await Notifier.refreshed(
                added: added,
                series: touched,
                checked: completed,
                failures: failures
            )
        }

        private func walk(collection: CollectionRecord.ID?, order: Order) async {
            let work: [Series]
            do {
                work = try await database.reader.read { [registry] db in
                    try Self.work(collection: collection, order: order, registry: registry, in: db)
                }
            } catch {
                log.log("library refresh could not build its work list - \(error)", level: .error, category: "refresh")
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

            // a hosted run leaves this to the launch handler, which re-arms only
            // after the task it was launched for is completed
            if !hosted { schedule() }
        }

        // re-armed at the end of every run and at launch, never only on
        // backgrounding: suwatte submits solely from its scene-phase hook and
        // its handler never re-submits, so its scheduling can stop for good
        // asap drops the earliest date rather than starting anything: the launch
        // stays the system's decision, this only removes the floor it was told to
        // wait behind. the next launch re-arms at the interval, so an asap
        // request that never ran does not persist
        func schedule(asap: Bool = false) {
            let automatic = UserDefaults.standard.bool(forKey: Preferences.Key.refreshAutomatic)

            #if targetEnvironment(simulator)
            log.log("scheduled refresh skipped - the simulator never accepts one", category: "refresh")
            #else
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Constants.Tasks.scheduledRefresh)
            guard automatic else {
                log.log("scheduled refresh cancelled - automatic checks are off", category: "refresh")
                return
            }

            let request = BGProcessingTaskRequest(identifier: Constants.Tasks.scheduledRefresh)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = asap ? nil : anchor.addingTimeInterval(Constants.Refresh.automaticInterval)

            do {
                try BGTaskScheduler.shared.submit(request)
                // an accepted submit says nothing on its own, and a silent
                // success is indistinguishable from a call that never happened
                log.log(
                    "scheduled refresh armed - \(request.earliestBeginDate.map { "no earlier than \($0.formatted())" } ?? "at the system's next opportunity")",
                    category: "refresh"
                )
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
            guard defaults.bool(forKey: Preferences.Key.refreshAutomatic), !isRunning else { return }

            guard let last = defaults.object(forKey: Preferences.Key.refreshedAutomaticallyDate) as? Date else {
                // a first-ever launch stamps and waits rather than walking a
                // library that was only just added
                defaults.set(Date.now, forKey: Preferences.Key.refreshedAutomaticallyDate)
                schedule()
                return
            }

            let due = last.addingTimeInterval(Constants.Refresh.automaticInterval)
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

        // only the continued-processing task, which iOS 26 exempts from having to
        // register before launch ends - so it stays with the owner that submits
        // it. the scheduled task is registered by Launch, during launch itself,
        // because a system-started launch has no screens to reach this from
        func register() {
            task.register { [weak self] in self?.cancel() }
        }

        // the system launched us to run this. the graph was built to get here, so
        // the run starts now and the task is held open until it ends
        func adopt(_ task: BGTask) {
            task.expirationHandler = { Task { @MainActor [weak self] in self?.cancel() } }
            hosted = true
            start(automatic: true)

            Task { @MainActor [weak self] in
                guard let self else { return task.setTaskCompleted(success: false) }

                // the run owns its own completion, so this waits on it rather
                // than returning and letting the system reclaim the process
                // mid-walk
                while self.isRunning {
                    try? await Task.sleep(for: .seconds(1))
                }

                // completed first, re-armed second, and the order is the whole
                // point: a request submitted while this task is still open
                // replaces the one the app was launched to run, and the system
                // may suspend us on the spot - which would be before
                // setTaskCompleted, leaving the task open and the next run
                // scheduled by a process that never said it had finished
                task.setTaskCompleted(success: true)
                self.hosted = false
                self.schedule()
            }
        }

#if DEBUG
        // MARK: Rehearsal

        // a rehearsal of the scheduled run, for a device you are holding.
        //
        // nothing can make ios decide to run a BGProcessingTask now - that
        // decision is its own and the api offers no override - so this fakes the
        // launch it would have made, using the same private hook the debugger
        // uses. everything downstream is the real path: the registered handler,
        // adopt, the hosted flag, rotation ordering, the notification, the
        // re-arm. only the system's choice of moment is fabricated.
        //
        // the five seconds is the point of the exercise rather than a wait for
        // state to settle: it puts the run after the screen is off, which is
        // where the real one lives. the background assertion buys roughly thirty
        // seconds, which is close to what a real run gets before an unlock ends
        // it - so a walk that does not finish here is representative, not broken.
        //
        // never ships. release builds have no reference to any of it
        func rehearse() async {
            guard !isRunning else { return }
            guard UserDefaults.standard.bool(forKey: Preferences.Key.refreshAutomatic) else {
                log.log("rehearsal skipped - automatic checks are off", category: "refresh")
                return
            }

            let app = UIApplication.shared
            var assertion = UIBackgroundTaskIdentifier.invalid

            // taken before the wait, or the process is suspended during it and
            // the wait never finishes
            assertion = app.beginBackgroundTask(withName: "refresh.rehearsal") {
                guard assertion != .invalid else { return }
                app.endBackgroundTask(assertion)
                assertion = .invalid
            }

            // the assertion's budget is the harness's alone - a real scheduled
            // run is granted minutes rather than this - so it is worth reading
            // rather than assuming. a truncated rehearsal is this number running
            // out, not the feature failing
            let budget = app.backgroundTimeRemaining
            let allowance = budget > 1e6 ? "unbounded" : "\(Int(budget))s"
            // the hook fakes the launch of a request that is already pending, and
            // firing it consumes that request - so a second rehearsal in a row
            // finds nothing to launch unless the schedule is re-armed first
            schedule()

            log.log("rehearsal armed - firing in 5s, assertion allows \(allowance)", category: "refresh")

            try? await Task.sleep(for: .seconds(5))

            let pending = await BGTaskScheduler.shared.pendingTaskRequests()
            guard pending.contains(where: { $0.identifier == Constants.Tasks.scheduledRefresh }) else {
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
                // the hook is undocumented, so it is allowed to disappear. the
                // walk is still worth exercising without it - what is lost is the
                // handler, not the run
                log.log("rehearsal - no simulate hook, starting the walk directly", level: .warning, category: "refresh")
                start(automatic: true)
            }

            // the handler cannot start anything synchronously - it has to resolve
            // the graph first - so the run does not exist the moment the hook
            // returns. waiting for the end before the beginning sees "not
            // running", calls it finished and drops the assertion, which leaves
            // the real walk running unprotected until the system suspends it
            var settling = 0
            while !isRunning && settling < 100 {
                try? await Task.sleep(for: .milliseconds(100))
                settling += 1
            }

            guard isRunning else {
                log.log("rehearsal - the launch never produced a run", level: .warning, category: "refresh")
                if assertion != .invalid { app.endBackgroundTask(assertion) }
                return
            }

            log.log("rehearsal - run started, holding the assertion open", category: "refresh")

            // a walk that goes quiet is the thing worth seeing, and silence
            // cannot say whether it is working or wedged. so it says where it is
            // every ten seconds, and gives up after five minutes rather than
            // holding the assertion forever on a stuck origin
            // finish() clears `total` but not `completed`, so a tick that lands
            // after the run ended reads "16 of 0". holding the last non-zero
            // total is enough to report honestly, and `completed` can be read
            // live - snapshotting that one instead just reported the count from
            // a second before the end
            var elapsed = 0
            var walked = 0
            while isRunning {
                if total > 0 { walked = total }

                try? await Task.sleep(for: .seconds(1))
                elapsed += 1

                if elapsed % 10 == 0 {
                    // the origins, not `current` - that is the last series
                    // dispatched, which with more than one in flight is as likely
                    // to name a bystander as the culprit
                    let stuck = await worker.outstanding()
                    log.log(
                        "rehearsal at \(elapsed)s - \(completed)/\(max(walked, total)) done, \(queued.count) queued, waiting on [\(stuck.joined(separator: ", "))]",
                        category: "refresh"
                    )
                }

                if elapsed >= 300 {
                    log.log("rehearsal giving up after 5m - cancelling", level: .warning, category: "refresh")
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
        order: Order,
        registry: Compositor.Registry,
        in db: Database
    ) throws -> [Series] {
        let ordering = order.clause
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

    // a run you are watching goes in the order you set. a run nobody is watching
    // goes least-recently-checked first, because it can be cut short at any
    // moment - the device unlocking is enough - and a stable order means a
    // truncated walk always covers the same head of the library, leaving the
    // tail permanently unchecked. rotating makes a short run cumulative instead
    enum Order: Sendable {
        case library(LibrarySort, ascending: Bool)
        case rotation

        var clause: String {
            switch self {
            case let .library(sort, ascending):
                "e.\(column(for: sort)) \(ascending ? "ASC" : "DESC")"

            // per series, not per origin: the walk's unit is a series and its
            // origins are checked together, so the oldest attempt among them is
            // what says how stale the series is. a series skipped by preference
            // never moves its dates, so turning a skip off sorts those to the
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

            // both parties get to call it finished, and either one is enough.
            // the reader's status is the stronger signal: a source that does not
            // track publication state reports ongoing forever, and the provider
            // column only moves when the series is opened, since the bulk walk
            // fetches chapters and not metadata. requiring agreement would mean
            // a reader who marked a series completed keeps paying for it on
            // every walk for as long as the source stays vague
            if completed {
                parts.append("AND e.\(EntryView.Columns.status.name) != '\(Status.completed.rawValue)'")
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
    // when each in-flight origin was dispatched, so a stalled one can say how
    // long it has been stalled rather than only that it exists
    private var started: [OriginRecord.ID: Date] = [:]

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
            log.log("origin \(originId.rawValue) already in flight, joining", level: .debug, category: "refresh")
            return await existing.value
        }

        // only completion was ever logged, so an origin that never appears could
        // equally have never started or started and hung - two different bugs
        // wearing one silence
        log.log("origin \(originId.rawValue) (\(source.descriptor.slug)) starting", level: .debug, category: "refresh")
        started[originId] = Date.now

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

    // what is outstanding right now, oldest first, for a caller that has gone
    // quiet and needs to say which origin it is waiting on rather than which
    // series happened to be dispatched last
    func outstanding() -> [String] {
        let now = Date.now
        return inFlight.keys
            .map { ($0, now.timeIntervalSince(started[$0] ?? now)) }
            .sorted { $0.1 > $1.1 }
            .map { "origin \($0.0.rawValue) (\(Int($0.1))s)" }
    }

    // metadata is a separate half so a library walk can skip it, and now
    // separate again so a metadata-only refresh can skip chapters. the
    // outcome mirrors chapters() - cancellation and failure are handled the
    // same way, only the success case differs, since there is no count to
    // report
    func metadata(source: Source, seriesSlug: String, originId: OriginRecord.ID) async -> MetadataOutcome {
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

            // the source, not just the origin id: a failure line is the one thing
            // read without any surrounding context, and a rowid alone cannot say
            // whether one site is having a bad day or the whole run went wrong
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
    // metadata a refresh is allowed to overwrite. titles and covers are add-only,
    // so a pick the user made can never be taken away by a later fetch.
    // returns whether the core fields actually changed, so a metadata-only
    // refresh can tell "updated" from "unchanged" rather than reporting success
    // for every request that merely landed
    nonisolated fileprivate static func write(
        _ detail: SeriesDetail,
        for originId: OriginRecord.ID,
        source: String,
        in db: Database
    ) throws -> Bool {
        guard let origin = try OriginRecord.fetchOne(db, key: originId.rawValue) else { return false }

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
                TitleRecord(id: nil, seriesId: origin.seriesId, metadataId: metadataId, value: value),
                in: db
            )
        }

        for url in detail.covers {
            _ = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: origin.seriesId, metadataId: metadataId, url: url, path: nil),
                in: db
            )
        }

        return changed
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

    // Library's "Last Updated" sort and Home's "New Chapters" both key off
    // recency, so this recomputes from scratch across every origin rather than
    // taking the max of old-vs-new - the only way both stay honest when a
    // second source's chapters land, or a republished date corrects one down
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

        guard var series = try SeriesRecord.fetchOne(db, key: seriesId.rawValue) else { return false }
        return try series.updateChanges(db) {
            $0.updatedDate = latest
        }
    }
}

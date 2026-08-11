//
//  Compositor+Trackers.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation

extension Compositor {
    // what screens hold. accounts, coarse counters, and which series are talking
    // to a service right now. deliberately without the collection-vs-item split
    // downloads has - a push is one request with no sub-progress.
    // see docs/features/trackers.md §9
    @MainActor
    @Observable
    final class Trackers {
        private let database: DatabaseClient
        private let authority: TrackerAuthority
        private let worker: TrackerSyncer
        private let log: AppLog

        private(set) var accounts: [Tracker: TrackerCredential] = [:]
        private(set) var pending = 0
        private(set) var failing = 0
        // which SERIES ON WHICH SERVICE has a push in flight. keyed by the pair
        // rather than the series: a series-only key made every tracker row on
        // that series spin whenever any one of them was working, so linking
        // anilist span myanimelist's row too
        private(set) var active: Set<Sync> = []

        struct Sync: Hashable, Sendable {
            let series: Int64
            let tracker: Tracker
        }
        // the one tracker failure a reader has to act on: an account has died and
        // nothing will sync until they sign in again.
        //
        // an accelerant rather than the record - it flips the UI the moment a push
        // proves the token is dead, where the credential's own
        // needsReauthentication says the same thing durably and survives a
        // relaunch. read `signedOut` rather than this set anywhere it matters
        private(set) var deadAccounts: Set<Tracker> = []

        // every connected service that cannot push until the reader signs in
        // again, whichever way it got there: anilist's year running out and
        // myanimelist's refresh token being refused now leave the same signature
        var needingSignIn: Set<Tracker> {
            let stranded = accounts.filter { $0.value.needsReauthentication }.keys
            return Set(stranded).union(deadAccounts.filter { accounts[$0] != nil })
        }

        // one lane per service. a lane in flight is also the guard against the
        // observation restarting it: the walk writes to the same table the
        // observation watches, so every successful push wakes it, and a wake
        // that cancelled the walk doing the work drained one row per debounce
        @ObservationIgnored private var drains: [Tracker: Task<Void, Never>] = [:]
        @ObservationIgnored private var watch: Task<Void, Never>?

        var isConnected: Bool { !accounts.isEmpty }

        nonisolated init(
            database: DatabaseClient,
            authority: TrackerAuthority,
            services: [Tracker: any TrackerService],
            log: AppLog = .shared
        ) {
            self.database = database
            self.authority = authority
            self.worker = TrackerSyncer(database: database, authority: authority, services: services, log: log)
            self.log = log
        }

        // MARK: Accounts

        func hydrate() {
            accounts = authority.accounts()
        }

        func authorization(for tracker: Tracker) throws -> TrackerAuthority.Authorization {
            try authority.authorization(for: tracker)
        }

        func complete(_ callback: URL, with authorization: TrackerAuthority.Authorization) async throws {
            let credential = try await authority.complete(callback, with: authorization)
            accounts[authorization.tracker] = credential
            deadAccounts.remove(authorization.tracker)
            // a reader who has just signed back in is owed the pushes that piled
            // up while they were not
            schedule()
        }

        func signOut(_ tracker: Tracker) async {
            await authority.signOut(tracker)
            accounts[tracker] = nil
            deadAccounts.remove(tracker)
        }

        // MARK: Draining

        // one observation rather than a call at every site that records reading.
        // the pending columns are the queue, so anything that writes them - the
        // reader, a batch mark, an attach watermark, an edit sheet - wakes this
        // without having to know it exists
        func restore() {
            guard watch == nil else { return }

            watch = Task { [weak self, database] in
                let observation = ValueObservation.tracking { db in
                    try SeriesTrackerRecord
                        .filter(SeriesTrackerRecord.Columns.pendingProgress != nil
                                || SeriesTrackerRecord.Columns.pendingStatus != nil)
                        .fetchCount(db)
                }

                do {
                    for try await count in observation.values(in: database.reader) {
                        guard let self else { return }
                        if count != self.pending { self.pending = count }
                        if count > 0 { self.schedule() }
                    }
                } catch {
                    self?.log.log("tracker queue observation FAILED - \(error)", category: "trackers")
                }
            }

            refreshCounts()
        }

        // no delay. a debounce was here to collapse a sitting of chapters into
        // one push, and it collapsed nothing: the queue is only written when the
        // chapter watermark moves, which is once per chapter finished, and those
        // are minutes apart. what it did do was add its whole length to every
        // sync, in front of a row that says "Syncing" for the duration
        func schedule() {
            guard isConnected else { return }
            for tracker in accounts.keys { start(tracker) }
        }

        func flush() {
            schedule()
        }

        // a lane per service, run side by side. the rate limits are per service
        // and nothing is shared between them - different hosts, different
        // tokens, and one database writer that serialises regardless - so the
        // only thing sequencing them together bought was a dead myanimelist
        // stopping anilist from finishing
        private func start(_ tracker: Tracker) {
            // a lane in flight re-reads the queue as it goes, so anything
            // dirtied under it is already picked up
            guard drains[tracker] == nil else { return }

            drains[tracker] = Task { [weak self] in
                await self?.run(tracker)
                self?.drains[tracker] = nil
            }
        }

        private func run(_ tracker: Tracker) async {
            defer { refreshCounts() }

            // one row is attempted at most once per walk. re-reading the queue
            // picks up anything dirtied while the walk was in flight, and the
            // processed set is what stops a row that cannot clear from spinning
            // the loop forever
            var processed: Set<Int64> = []
            // outside the loop, so the spacing survives a re-read of the queue
            var lastPush: Date?

            while !Task.isCancelled {
                let pending: [SeriesTrackerRecord]
                do {
                    pending = try await database.reader.read {
                        try SeriesTrackerRecord.dirty(for: tracker, in: $0)
                    }
                } catch {
                    log.log("[\(tracker.rawValue)] drain FAILED to read queue - \(error)", category: "trackers")
                    return
                }

                let links = pending.filter { $0.id.map { !processed.contains($0.rawValue) } ?? false }
                guard !links.isEmpty else { return }

                guard let credential = accounts[tracker] else { return }

                // a stranded credential is still a credential, so it passes the
                // check above - and spending a request to be told what the expiry
                // already says is a wasted round trip and a wasted halt. marked
                // and skipped here instead, with every pending column left where
                // it is
                guard !credential.needsReauthentication else {
                    if deadAccounts.insert(tracker).inserted {
                        log.log("[\(tracker.rawValue)] needs reauthentication - lane halted", category: "trackers")
                    }
                    return
                }

                log.log("[\(tracker.rawValue)] draining \(links.count) push(es)", category: "trackers")

                for link in links {
                    guard let id = link.id?.rawValue else { continue }
                    processed.insert(id)

                    let mark = Sync(series: link.seriesId.rawValue, tracker: tracker)
                    active.insert(mark)
                    defer { active.remove(mark) }

                    // charged to the request it protects rather than to the one
                    // before it. paced after the last push, the lane sat awake
                    // for the whole spacing with nothing left to space out
                    if let lastPush {
                        await pace(tracker, since: lastPush)
                    }

                    do {
                        try await worker.push(link)
                        lastPush = .now
                    } catch let error as TrackerError where error.isTerminal {
                        // one clear stop rather than forty identical failures,
                        // the same rule the download queue uses when the disk is
                        // full. this lane only: the other service's token is
                        // fine and its rows are owed their pushes. every pending
                        // column survives for when they sign back in
                        log.log("[\(tracker.rawValue)] lane halted - \(error.localizedDescription)", category: "trackers")
                        deadAccounts.insert(tracker)
                        // the keychain has just learned this token is dead. the
                        // in-memory copy every tracker row in the app reads has
                        // not, and without this they keep drawing it as healthy
                        // until the next launch
                        hydrate()
                        return
                    } catch {
                        // recorded on the row by the worker; the walk keeps going.
                        // a failed attempt still spent a request, so it still
                        // spaces the next one
                        lastPush = .now
                        continue
                    }
                }
            }
        }

        // a concurrency cap is not a rate limit: the host gate gives each service
        // three slots and paces neither. anilist is live at thirty a minute
        // against a documented ninety, and myanimelist answers a burst with a
        // five to ten minute ban and never a 429
        private func pace(_ tracker: Tracker, since last: Date) async {
            let spacing: Duration = switch tracker {
            case .anilist: .milliseconds(60_000 / Constants.Trackers.anilistRequestsPerMinute)
            case .myAnimeList: Constants.Trackers.malRequestSpacing
            }

            // the push that just ran counts toward the gap. a two-request push
            // takes most of a second on its own, and sleeping the full spacing
            // on top of that paces slower than the limit asks for
            let elapsed = Duration.seconds(Date.now.timeIntervalSince(last))
            guard elapsed < spacing else { return }

            try? await Task.sleep(for: spacing - elapsed)
        }

        func refreshCounts() {
            Task { [weak self, database] in
                let counts = try? await database.reader.read { db in
                    (
                        pending: try SeriesTrackerRecord
                            .filter(SeriesTrackerRecord.Columns.pendingProgress != nil
                                    || SeriesTrackerRecord.Columns.pendingStatus != nil)
                            .fetchCount(db),
                        failing: try SeriesTrackerRecord
                            .filter(SeriesTrackerRecord.Columns.syncError != nil)
                            .fetchCount(db)
                    )
                }
                guard let self, let counts else { return }
                if counts.pending != self.pending { self.pending = counts.pending }
                if counts.failing != self.failing { self.failing = counts.failing }
            }
        }

        // MARK: One series

        func search(_ tracker: Tracker, query: String, adult: Bool) async throws -> [TrackerCandidate] {
            try await worker.search(tracker, query: query, adult: adult)
        }

        // the media and the reader's own entry on it together, which is the same
        // call a push makes before it writes
        func entry(_ tracker: Tracker, remoteId: Int64) async throws -> TrackerEntry {
            try await worker.remote(tracker, remoteId: remoteId)
        }

        func link(
            series: SeriesRecord.ID,
            tracker: Tracker,
            candidate: TrackerCandidate,
            status: Status,
            update: TrackerUpdate? = nil
        ) async throws {
            let mark = Sync(series: series.rawValue, tracker: tracker)
            active.insert(mark)
            defer { active.remove(mark) }

            do {
                try await worker.link(
                    series: series,
                    tracker: tracker,
                    candidate: candidate,
                    status: status,
                    update: update
                )
            } catch {
                strand(tracker, on: error)
                throw error
            }
            refreshCounts()
        }

        // removing the entry from the reader's list is a separate, louder thing
        // than stopping the sync, and only they can say which they meant
        func unlink(_ link: SeriesTrackerRecord, removeRemote: Bool = false) async throws {
            try await worker.unlink(link, removeRemote: removeRemote)
            refreshCounts()
        }

        // an explicit edit is the one caller allowed to lower a number, and the
        // only one that may write to an entry the service calls finished
        func edit(_ link: SeriesTrackerRecord, update: TrackerUpdate) async throws {
            let mark = Sync(series: link.seriesId.rawValue, tracker: link.tracker)
            active.insert(mark)
            defer { active.remove(mark) }

            do {
                try await worker.edit(link, update: update)
            } catch {
                strand(link.tracker, on: error)
                throw error
            }
            refreshCounts()
        }

        // a dead token found anywhere other than the drain. the screen that hit
        // it shows the error itself, but every other tracker row in the app
        // reads the in-memory account copy - which is loaded at launch, and
        // would go on drawing this account as healthy until the next one
        private func strand(_ tracker: Tracker, on error: Error) {
            guard (error as? TrackerError)?.isTerminal == true else { return }
            deadAccounts.insert(tracker)
            hydrate()
        }

        func retry(_ link: SeriesTrackerRecord) {
            retry(link.tracker)
        }

        // the mark comes off before the lane starts, or it halts on the way in
        // at the same guard that set it
        func retry(_ tracker: Tracker) {
            deadAccounts.remove(tracker)
            flush()
        }

        func isSyncing(series: Int64) -> Bool {
            active.contains { $0.series == series }
        }

        func syncing(series: Int64) -> Set<Tracker> {
            Set(active.filter { $0.series == series }.map(\.tracker))
        }
    }
}

// MARK: - Worker

// the unit of work is one link row - one series on one service - exactly as
// refresh's unit is one origin. the only writer of series_tracker
actor TrackerSyncer {
    private let database: DatabaseClient
    private let authority: TrackerAuthority
    private let services: [Tracker: any TrackerService]
    private let log: AppLog

    init(
        database: DatabaseClient,
        authority: TrackerAuthority,
        services: [Tracker: any TrackerService],
        log: AppLog
    ) {
        self.database = database
        self.authority = authority
        self.services = services
        self.log = log
    }

    func search(_ tracker: Tracker, query: String, adult: Bool) async throws -> [TrackerCandidate] {
        let service = try service(for: tracker)
        return try await attempt(tracker) { try await service.search(query, adult: adult, token: $0) }
    }

    func remote(_ tracker: Tracker, remoteId: Int64) async throws -> TrackerEntry {
        let service = try service(for: tracker)
        return try await attempt(tracker) {
            try await service.entry(remoteId: remoteId, token: $0)
        }
    }

    // MARK: Link

    func link(
        series: SeriesRecord.ID,
        tracker: Tracker,
        candidate: TrackerCandidate,
        status: Status,
        update: TrackerUpdate? = nil
    ) async throws {
        let service = try service(for: tracker)

        let remote = try await attempt(tracker) {
            try await service.entry(remoteId: candidate.id, token: $0)
        }

        // seeding goes through the same max(remote, local) path an ordinary push
        // does, so there is no separate first-write to keep correct - and an
        // entry the reader already has at sixty is never dragged down to ours
        let (local, started) = try await database.reader.read { db in
            (
                try SeriesTrackerRecord.watermark(for: series, in: db),
                try Self.startDate(for: series, in: db)
            )
        }

        let progress = Self.clamp(update?.progress ?? max(remote.progress, local), to: remote.totalChapters)
        let seeded = try await write(
            TrackerUpdate(
                remoteId: candidate.id,
                entryId: remote.entryId,
                progress: progress > remote.progress || !remote.isListed ? progress : nil,
                status: update?.status ?? (remote.isListed ? nil : status),
                score: update?.score,
                startDate: remote.isListed ? nil : started
            ),
            service: service,
            tracker: tracker,
            existing: remote
        )

        var record = SeriesTrackerRecord(
            seriesId: series,
            tracker: tracker,
            remoteId: candidate.id,
            remoteEntryId: seeded.entryId,
            remoteTitle: seeded.title.isEmpty ? candidate.title : seeded.title,
            remoteStatus: seeded.status,
            remoteProgress: seeded.progress,
            remoteScore: seeded.score,
            totalChapters: seeded.totalChapters ?? candidate.totalChapters
        )
        record.syncedDate = .now
        record.attemptedDate = .now

        let row = record
        try await database.writer.write { db in
            var inserted = row
            try inserted.insert(db, onConflict: .replace)
        }

        log.log("[\(tracker.rawValue)] linked \(record.remoteTitle) at \(record.remoteProgress)", category: "trackers")
    }

    func unlink(_ link: SeriesTrackerRecord, removeRemote: Bool) async throws {
        guard let id = link.id else { return }

        // the local row goes whatever the service says: a link the reader has
        // removed must not come back because a request timed out
        defer {
            Task { [database] in
                try? await database.writer.write { db in
                    _ = try SeriesTrackerRecord.deleteOne(db, key: id.rawValue)
                }
            }
        }

        // the default stops the sync and leaves their list alone: a score, a
        // status and a start date live on that entry, and none of them came from
        // us. deleting it because a reader wanted to stop syncing would destroy
        // history this app never owned
        guard removeRemote else { return }

        guard let service = services[link.tracker], let token = try? await authority.token(for: link.tracker) else {
            return
        }

        let entry = TrackerEntry(
            remoteId: link.remoteId,
            title: link.remoteTitle,
            entryId: link.remoteEntryId
        )
        try? await service.delete(entry, token: token)
    }

    // MARK: Edit

    func edit(_ link: SeriesTrackerRecord, update: TrackerUpdate) async throws {
        let service = try service(for: link.tracker)

        let existing = TrackerEntry(
            remoteId: link.remoteId,
            title: link.remoteTitle,
            totalChapters: link.totalChapters,
            entryId: link.remoteEntryId,
            status: link.remoteStatus,
            progress: link.remoteProgress,
            score: link.remoteScore
        )

        do {
            let result = try await write(update, service: service, tracker: link.tracker, existing: existing)
            try await store(result, on: link, clearingQueue: true)
        } catch {
            try await record(failure: error, on: link)
            throw error
        }
    }

    // MARK: Push

    func push(_ link: SeriesTrackerRecord) async throws {
        guard let service = services[link.tracker] else { throw TrackerError.unavailable }

        do {
            // the fix for the one bug that loses data. without it: read to forty
            // here, to sixty on the website, then forty-one here, and an absolute
            // write of forty-one lands on top of sixty. costs one request
            let remote = try await attempt(link.tracker) {
                try await service.entry(remoteId: link.remoteId, token: $0)
            }

            // the enqueue-side check reads a cached column, which is a guess at
            // what the service holds. this is the live answer, and the only one
            // that is right when the reader finished the series on the website.
            // a queued .reading is the automatic promotion and defers to it; any
            // other pending status was picked by hand and travels
            let automatic = link.pendingStatus == nil || link.pendingStatus == .reading

            // declining has to CLEAR the queue, not skip it. a pending column
            // left in place is re-read, re-declined and left again on every
            // drain, forever, at two requests a time
            guard remote.status != .completed || !automatic else {
                // the service already calls it finished, so there is nothing to
                // say - and it will never accept these numbers, so the queue is
                // dropped outright rather than compared against a progress that
                // cannot move. comparing would leave a higher pending value in
                // place and re-run this every drain, forever
                var settled = remote
                settled.status = .completed
                try await store(settled, on: link, clearingQueue: true, force: true)
                return
            }

            let target = Self.clamp(
                max(remote.progress, link.pendingProgress ?? 0),
                to: remote.totalChapters ?? link.totalChapters
            )

            var result = remote

            if target > remote.progress {
                result = try await write(
                    TrackerUpdate(remoteId: link.remoteId, entryId: remote.entryId, progress: target),
                    service: service,
                    tracker: link.tracker,
                    existing: remote
                )
            }

            // status travels on its own, never in the same write as a progress
            // value: anilist rewrites progress server-side on COMPLETED and
            // zeroes it on REPEATING, so the two together do not both stick
            if let status = link.pendingStatus, status != result.status {
                result = try await write(
                    TrackerUpdate(remoteId: link.remoteId, entryId: result.entryId, status: status),
                    service: service,
                    tracker: link.tracker,
                    existing: result
                )
            }

            try await store(result, on: link, clearingQueue: true)
        } catch {
            try await record(failure: error, on: link)
            throw error
        }
    }

    // MARK: Writing

    // the response is the only proof of what landed. anilist rewrites fields
    // server-side on a status change, and myanimelist answers 200 for a body it
    // ignored, so nothing here trusts what it sent
    private func write(
        _ update: TrackerUpdate,
        service: any TrackerService,
        tracker: Tracker,
        existing: TrackerEntry
    ) async throws -> TrackerEntry {
        guard update.progress != nil || update.status != nil || update.score != nil || update.startDate != nil else {
            return existing
        }

        return try await attempt(tracker) { try await service.save(update, token: $0) }
    }

    private func store(
        _ entry: TrackerEntry,
        on link: SeriesTrackerRecord,
        clearingQueue: Bool,
        // drop the queue whatever it holds, for the one case where no future
        // attempt can ever satisfy it
        force: Bool = false
    ) async throws {
        guard let id = link.id else { return }

        try await database.writer.write { db in
            guard var row = try SeriesTrackerRecord.fetchOne(db, key: id.rawValue) else { return }

            row.remoteEntryId = entry.entryId ?? row.remoteEntryId
            if !entry.title.isEmpty { row.remoteTitle = entry.title }
            row.remoteStatus = entry.status ?? row.remoteStatus
            row.remoteProgress = entry.progress
            row.remoteScore = entry.score
            row.totalChapters = entry.totalChapters ?? row.totalChapters
            row.syncedDate = .now
            row.attemptedDate = .now
            row.syncError = nil

            if clearingQueue {
                // only what this push answered for. a chapter finished while the
                // request was in flight has already written a higher number, and
                // clearing it blind would lose that read until the next one
                if force || (row.pendingProgress.map { $0 <= entry.progress } ?? false) {
                    row.pendingProgress = nil
                }
                if force || (row.pendingStatus.map { $0 == entry.status } ?? false) {
                    row.pendingStatus = nil
                }
            }

            try row.update(db)
        }
    }

    private func record(failure: Error, on link: SeriesTrackerRecord) async throws {
        guard let id = link.id else { return }

        let reason = (failure as? TrackerError)?.errorDescription
            ?? (failure as? LocalizedError)?.errorDescription
            ?? "Sync failed"

        log.log("[\(link.tracker.rawValue)] \(link.remoteTitle) - \(reason)", category: "trackers")

        // a terminal error is a fact about the ACCOUNT, and writing it to a link
        // row brands one series with it - whichever the walk happened to reach
        // first, while the rest sit pending and silent. the only badge in the app
        // would then point at a series that is not the problem. the attempt is
        // still stamped, because it was attempted; the reason is not, because the
        // reason does not belong to this series. an account says it once, where
        // signing in again is possible
        let blames = (failure as? TrackerError)?.isTerminal != true

        try await database.writer.write { db in
            _ = try SeriesTrackerRecord
                .filter(key: id.rawValue)
                .updateAll(db, [
                    SeriesTrackerRecord.Columns.attemptedDate.set(to: Date.now),
                    SeriesTrackerRecord.Columns.syncError.set(to: blames ? reason : nil)
                ])
        }
    }

    // MARK: Helpers

    private func service(for tracker: Tracker) throws -> any TrackerService {
        guard let service = services[tracker] else { throw TrackerError.unavailable }
        return service
    }

    // one refresh and one retry, and only for a token the service says is dead.
    // a second failure is the reader's to fix
    private func attempt<Value>(
        _ tracker: Tracker,
        _ work: (String) async throws -> Value
    ) async throws -> Value {
        let token = try await authority.token(for: tracker)
        do {
            return try await work(token)
        } catch TrackerError.reauthenticationRequired {
            let fresh = try await authority.recover(tracker)
            return try await work(fresh)
        }
    }

    // a scraper's phantom chapter 999 must not complete a series, and a null
    // total is an ongoing work rather than a zero
    private static func clamp(_ progress: Int, to total: Int?) -> Int {
        guard let total, total > 0 else { return max(0, progress) }
        return min(max(0, progress), total)
    }

    // back-dated from the earliest recorded read, which is the closest thing to
    // when the reader actually started. addedDate is the fallback, and nothing
    // ever back-dates a finish date - we cannot know it
    private static func startDate(for series: SeriesRecord.ID, in db: Database) throws -> Date? {
        if let earliest = try Date.fetchOne(db, sql: """
            SELECT MIN(\(ReadingEventRecord.Columns.occurredDate.name))
            FROM \(ReadingEventRecord.databaseTableName)
            WHERE \(ReadingEventRecord.Columns.seriesId.name) = ?
            """, arguments: [series.rawValue]) {
            return earliest
        }

        let added = try SeriesRecord.fetchOne(db, key: series.rawValue)?.addedDate
        return added == .distantPast ? nil : added
    }
}


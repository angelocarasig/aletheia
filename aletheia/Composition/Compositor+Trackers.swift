//
//  Compositor+Trackers.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Observation
import Tagged

extension Compositor {
    // deliberately without the collection-vs-item split Downloads has - a push
    // is one request with no sub-progress. see docs/features/trackers.md §9
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
        // keyed by the series/tracker pair, not just the series - a series-only
        // key previously made every tracker row on a series spin whenever any
        // one of them was working, so linking anilist span myanimelist's row too
        private(set) var active: Set<Sync> = []

        struct Sync: Hashable, Sendable {
            let series: Int64
            let tracker: Tracker
        }

        // an accelerant, not the record - flips the UI the moment a push proves
        // the token is dead, where the credential's own needsReauthentication
        // says the same thing durably. read `needingSignIn` below instead
        // anywhere it matters, since this set does not survive a relaunch
        private(set) var deadAccounts: Set<Tracker> = []

        // unifies two different failure signatures: anilist's year running out
        // and myanimelist's refresh token being refused both end up here
        var needingSignIn: Set<Tracker> {
            let stranded = accounts.filter { $0.value.needsReauthentication }.keys
            return Set(stranded).union(deadAccounts.filter { accounts[$0] != nil })
        }

        // a lane in flight guards against the observation restarting it - the
        // walk writes to the same table the observation watches, so every
        // successful push wakes it, and without the guard that wake would
        // cancel the walk doing the work and drain one row per debounce
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
            self.worker = TrackerSyncer(
                database: database, authority: authority, services: services, log: log)
            self.log = log
        }

        // MARK: Accounts

        func hydrate() {
            accounts = authority.accounts()
        }

        func authorization(for tracker: Tracker) throws -> TrackerAuthority.Authorization {
            try authority.authorization(for: tracker)
        }

        func complete(_ callback: URL, with authorization: TrackerAuthority.Authorization)
            async throws
        {
            let credential = try await authority.complete(callback, with: authorization)
            accounts[authorization.tracker] = credential
            deadAccounts.remove(authorization.tracker)
            schedule()
        }

        func signIn(token: String, for tracker: Tracker) async throws {
            let credential = try await authority.signIn(token: token, for: tracker)
            accounts[tracker] = credential
            deadAccounts.remove(tracker)
            schedule()
        }

        func signOut(_ tracker: Tracker) async {
            await authority.signOut(tracker)
            accounts[tracker] = nil
            deadAccounts.remove(tracker)
        }

        // MARK: Draining

        // one observation rather than a call at every site that records reading -
        // anything that writes the pending columns wakes this without needing to
        // know it exists
        func restore() {
            guard watch == nil else { return }

            watch = Task { [weak self, database] in
                let observation = ValueObservation.tracking { db in
                    try SeriesTrackerRecord
                        .filter(
                            SeriesTrackerRecord.Columns.pendingProgress != nil
                                || SeriesTrackerRecord.Columns.pendingStatus != nil
                        )
                        .fetchCount(db)
                }

                do {
                    for try await count in observation.values(in: database.reader) {
                        guard let self else { return }
                        if count != self.pending { self.pending = count }
                        if count > 0 { self.schedule() }
                    }
                } catch {
                    self?.log.log(
                        "tracker queue observation FAILED - \(error)", level: .error,
                        category: "trackers")
                }
            }

            refreshCounts()
        }

        // a debounce used to sit here to collapse a run of chapters into one
        // push, but the queue only writes once per chapter finished - minutes
        // apart - so it collapsed nothing and only added its length to every
        // sync's "Syncing" row
        func schedule() {
            guard isConnected else { return }
            for tracker in accounts.keys { start(tracker) }
        }

        func flush() {
            schedule()
        }

        // lanes run side by side - rate limits are per service and nothing is
        // shared between them, so sequencing them would only buy a dead
        // myanimelist stopping anilist from finishing
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

            // stops a row that cannot clear from spinning the loop forever
            var processed: Set<Int64> = []
            var lastPush: Date?

            while !Task.isCancelled {
                let pending: [SeriesTrackerRecord]
                do {
                    pending = try await database.reader.read {
                        try SeriesTrackerRecord.dirty(for: tracker, in: $0)
                    }
                } catch {
                    log.log(
                        "[\(tracker.rawValue)] drain FAILED to read queue - \(error)",
                        level: .error, category: "trackers")
                    return
                }

                let links = pending.filter {
                    $0.id.map { !processed.contains($0.rawValue) } ?? false
                }
                guard !links.isEmpty else { return }

                guard let credential = accounts[tracker] else { return }

                // a stranded credential still passes the nil check above -
                // spending a request to be told what the expiry already says
                // would be a wasted round trip, so it's marked and skipped here
                // instead, with every pending column left where it is
                guard !credential.needsReauthentication else {
                    if deadAccounts.insert(tracker).inserted {
                        log.log(
                            "[\(tracker.rawValue)] needs reauthentication - lane halted",
                            level: .warning, category: "trackers")
                    }
                    return
                }

                log.log(
                    "[\(tracker.rawValue)] draining \(links.count) push(es)", category: "trackers")

                for link in links {
                    guard let id = link.id?.rawValue else { continue }
                    processed.insert(id)

                    let mark = Sync(series: link.seriesId.rawValue, tracker: tracker)
                    active.insert(mark)
                    defer { active.remove(mark) }

                    // charged to the request it protects, not the one before it -
                    // pacing after the last push instead left the lane awake for
                    // the whole spacing with nothing left to space out
                    if let lastPush {
                        await pace(tracker, since: lastPush)
                    }

                    do {
                        try await worker.push(link)
                        lastPush = .now
                    } catch let error as TrackerError where error.isTerminal {
                        // this lane only - the other service's token is fine and
                        // its rows are owed their pushes. every pending column
                        // survives for when they sign back in
                        log.log(
                            "[\(tracker.rawValue)] lane halted - \(error.localizedDescription)",
                            category: "trackers")
                        deadAccounts.insert(tracker)
                        // keychain has just learned this token is dead - without
                        // this, every other tracker row's in-memory copy keeps
                        // drawing it as healthy until the next launch
                        hydrate()
                        return
                    } catch {
                        // a failed attempt still spent a request, so it still
                        // spaces the next one
                        lastPush = .now
                        continue
                    }
                }
            }
        }

        // a concurrency cap is not a rate limit - the host gate gives each
        // service three slots and paces neither. anilist runs at thirty a
        // minute against a documented ninety; myanimelist answers a burst with
        // a five-to-ten-minute ban and never a 429; mangabaka publishes 180 a
        // minute and this sits well under it. none of the three expose
        // rate-limit headers, so open-loop pacing against these constants is
        // all any of them get
        private func pace(_ tracker: Tracker, since last: Date) async {
            let spacing: Duration =
                switch tracker {
                case .anilist: .milliseconds(60_000 / Constants.Trackers.anilistRequestsPerMinute)
                case .myAnimeList: Constants.Trackers.malRequestSpacing
                case .mangaBaka:
                    .milliseconds(60_000 / Constants.Trackers.mangaBakaRequestsPerMinute)
                }

            // the push that just ran counts toward the gap - sleeping the full
            // spacing on top of it would pace slower than the limit asks for
            let elapsed = Duration.seconds(Date.now.timeIntervalSince(last))
            guard elapsed < spacing else { return }

            try? await Task.sleep(for: spacing - elapsed)
        }

        func refreshCounts() {
            Task { [weak self, database] in
                let counts = try? await database.reader.read { db in
                    (
                        pending:
                            try SeriesTrackerRecord
                            .filter(
                                SeriesTrackerRecord.Columns.pendingProgress != nil
                                    || SeriesTrackerRecord.Columns.pendingStatus != nil
                            )
                            .fetchCount(db),
                        failing:
                            try SeriesTrackerRecord
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

        func search(_ tracker: Tracker, query: String, adult: Bool) async throws
            -> [TrackerCandidate]
        {
            try await worker.search(tracker, query: query, adult: adult)
        }

        func entry(_ tracker: Tracker, remoteId: Int64) async throws -> TrackerEntry {
            try await worker.remote(tracker, remoteId: remoteId)
        }

        func list(_ tracker: Tracker) async throws -> [TrackerListEntry] {
            try await worker.list(tracker)
        }

        func refreshMetadata(_ link: SeriesTrackerRecord) async -> MetadataOutcome {
            await worker.refreshMetadata(link)
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

        func unlink(_ link: SeriesTrackerRecord, removeRemote: Bool = false) async throws {
            try await worker.unlink(link, removeRemote: removeRemote)
            refreshCounts()
        }

        // the one caller allowed to lower a number, and the only one that may
        // write to an entry the service already calls finished
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

        // a dead token found anywhere other than the drain - every other
        // tracker row in the app reads the in-memory account copy, which would
        // otherwise go on drawing this account as healthy until the next launch
        private func strand(_ tracker: Tracker, on error: Error) {
            guard (error as? TrackerError)?.isTerminal == true else { return }
            deadAccounts.insert(tracker)
            hydrate()
        }

        func retry(_ link: SeriesTrackerRecord) {
            retry(link.tracker)
        }

        // the mark must come off before the lane starts, or it halts on the way
        // in at the same guard that set it
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

// the only writer of series_tracker
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
        return try await attempt(tracker) {
            try await service.search(query, adult: adult, token: $0)
        }
    }

    func remote(_ tracker: Tracker, remoteId: Int64) async throws -> TrackerEntry {
        let service = try service(for: tracker)
        return try await attempt(tracker) {
            try await service.entry(remoteId: remoteId, token: $0)
        }
    }

    // the caller (Tracker Restore) is expected to have checked BulkListingTracker
    // conformance before offering the tracker as a source at all
    func list(_ tracker: Tracker) async throws -> [TrackerListEntry] {
        guard let service = try service(for: tracker) as? BulkListingTracker else {
            throw TrackerError.unavailable
        }
        return try await attempt(tracker) { try await service.list(token: $0) }
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

        // same max(remote, local) path an ordinary push uses - an entry the
        // reader already has at sixty is never dragged down to ours
        let (local, started) = try await database.reader.read { db in
            (
                try SeriesTrackerRecord.furthest(for: series, in: db),
                try Self.startDate(for: series, in: db)
            )
        }

        let progress = Self.clamp(
            update?.progress ?? max(remote.progress, local), to: remote.totalChapters)
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
            // `remote`, not `seeded` - the save mutation answers with a trimmed
            // media, while the entry read carries the whole thing
            try Self.absorb(remote, tracker: tracker, series: series, link: inserted.id, in: db)
        }

        log.log(
            "[\(tracker.rawValue)] linked \(record.remoteTitle) at \(record.remoteProgress)",
            category: "trackers")
    }

    // tags are the exception and go straight onto the series - a tag does not
    // care where it came from
    @discardableResult
    nonisolated static func absorb(
        _ entry: TrackerEntry,
        tracker: Tracker,
        series: SeriesRecord.ID,
        link: SeriesTrackerRecord.ID?,
        in db: Database
    ) throws -> Bool {
        var metadata = try MetadataRecord.adopt(
            seriesId: series,
            supplier: MetadataRecord.supplier(tracker: tracker),
            trackerId: link,
            in: db
        )

        let changed = try metadata.updateChanges(db) {
            $0.synopsis = tracker.storesProse ? (entry.synopsis ?? "") : ""
            $0.classification = entry.classification
            $0.publication = entry.publication
            $0.fetchedDate = .now
        }

        guard let metadataId = metadata.id else { return changed }

        for value in entry.titles where !value.isEmpty {
            _ = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: series, metadataId: metadataId, value: value),
                in: db
            )
        }

        for url in entry.covers {
            _ = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: series, metadataId: metadataId, url: url, path: nil),
                in: db
            )
        }

        for name in entry.tags {
            try TagRecord.attach(name, to: series, in: db)
        }

        return changed
    }

    // closes the gap tracker-metadata.md records: absorb previously ran only at
    // link time and never again
    func refreshMetadata(_ link: SeriesTrackerRecord) async -> MetadataOutcome {
        do {
            let entry = try await remote(link.tracker, remoteId: link.remoteId)
            let changed = try await database.writer.write { db in
                try Self.absorb(
                    entry, tracker: link.tracker, series: link.seriesId, link: link.id, in: db)
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
                "[\(link.tracker.rawValue)] metadata refresh failed - \(error)",
                level: .error,
                category: "trackers"
            )
            return .failed(reason)
        }
    }

    func unlink(_ link: SeriesTrackerRecord, removeRemote: Bool) async throws {
        guard let id = link.id else { return }

        // the local row goes regardless of what the service says - a link the
        // reader has removed must not come back because a request timed out
        defer {
            Task { [database] in
                try? await database.writer.write { db in
                    _ = try SeriesTrackerRecord.deleteOne(db, key: id.rawValue)
                }
            }
        }

        // the default stops the sync and leaves their remote entry alone - a
        // score, status and start date live on it that never came from us, and
        // deleting it would destroy history this app never owned
        guard removeRemote else { return }

        guard let service = services[link.tracker],
            let token = try? await authority.token(for: link.tracker)
        else {
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
            let result = try await write(
                update, service: service, tracker: link.tracker, existing: existing)
            try await store(result, on: link, clearingQueue: true)
        } catch {
            try await record(failure: error, on: link)
            throw error
        }
    }

    // MARK: Push

    func push(_ link: SeriesTrackerRecord) async throws {
        guard let service = services[link.tracker] else { throw TrackerError.unavailable }
        var link = link

        do {
            // the fix for the one bug that loses data: without re-reading first,
            // "read 40 here, 60 on the website, then 41 here" ends with an
            // absolute write of 41 landing on top of 60. costs one request
            let remote = try await attempt(link.tracker) {
                try await service.entry(remoteId: link.remoteId, token: $0)
            }

            // a service that merges two entries answers under the successor's id;
            // the writes below address link.remoteId, so without adopting the
            // hop here the entry is read from one id and written to another
            if remote.remoteId != link.remoteId {
                log.log(
                    "[\(link.tracker.rawValue)] \(link.remoteTitle) merged \(link.remoteId) -> \(remote.remoteId)",
                    category: "trackers"
                )
                link.adopt(remoteId: remote.remoteId)
                try await adopt(remoteId: remote.remoteId, on: link)
            }

            // a queued .reading is the automatic promotion and defers to the
            // live answer; any other pending status was picked by hand and travels
            let automatic = link.pendingStatus == nil || link.pendingStatus == .reading

            // must CLEAR the queue, not skip it - a pending column left in place
            // is re-read, re-declined and left again on every drain, forever
            guard remote.status != .completed || !automatic else {
                // dropped outright rather than compared against a progress that
                // cannot move - comparing would leave a higher pending value in
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
                    TrackerUpdate(
                        remoteId: link.remoteId, entryId: remote.entryId, progress: target),
                    service: service,
                    tracker: link.tracker,
                    existing: remote
                )
            }

            // never combined with a progress write - anilist rewrites progress
            // server-side on COMPLETED and zeroes it on REPEATING, so the two
            // together do not both stick
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

    // the response is the only proof of what landed - anilist rewrites fields
    // server-side on a status change, and myanimelist answers 200 for a body it
    // ignored, so nothing here trusts what it sent
    private func write(
        _ update: TrackerUpdate,
        service: any TrackerService,
        tracker: Tracker,
        existing: TrackerEntry
    ) async throws -> TrackerEntry {
        guard
            update.progress != nil || update.status != nil || update.score != nil
                || update.startDate != nil
        else {
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
                // only clears what this push answered for - a chapter finished
                // while the request was in flight already wrote a higher number,
                // and clearing blind would lose that read until the next push
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

    // written on its own, not folded into store() - a push that fails after the
    // hop should still leave the repaired id behind for the next attempt
    private func adopt(remoteId: Int64, on link: SeriesTrackerRecord) async throws {
        guard let id = link.id else { return }

        try await database.writer.write { db in
            guard var row = try SeriesTrackerRecord.fetchOne(db, key: id.rawValue) else { return }
            row.adopt(remoteId: remoteId)
            try row.update(db)
        }
    }

    private func record(failure: Error, on link: SeriesTrackerRecord) async throws {
        guard let id = link.id else { return }

        let reason =
            (failure as? TrackerError)?.errorDescription
            ?? (failure as? LocalizedError)?.errorDescription
            ?? "Sync failed"

        log.log("[\(link.tracker.rawValue)] \(link.remoteTitle) - \(reason)", category: "trackers")

        // a terminal error is a fact about the account, not this series - writing
        // it to this row would brand whichever series the walk happened to reach
        // first, and the app's only badge would point at a series that isn't the
        // problem. the attempt is still stamped, since it was attempted, but not the reason
        let blames = (failure as? TrackerError)?.isTerminal != true

        try await database.writer.write { db in
            _ =
                try SeriesTrackerRecord
                .filter(key: id.rawValue)
                .updateAll(
                    db,
                    [
                        SeriesTrackerRecord.Columns.attemptedDate.set(to: Date.now),
                        SeriesTrackerRecord.Columns.syncError.set(to: blames ? reason : nil),
                    ])
        }
    }

    // MARK: Helpers

    private func service(for tracker: Tracker) throws -> any TrackerService {
        guard let service = services[tracker] else { throw TrackerError.unavailable }
        return service
    }

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

    // a scraper's phantom chapter 999 must not complete a series - a null total
    // means ongoing, not zero
    private static func clamp(_ progress: Int, to total: Int?) -> Int {
        guard let total, total > 0 else { return max(0, progress) }
        return min(max(0, progress), total)
    }

    private static func startDate(for series: SeriesRecord.ID, in db: Database) throws -> Date? {
        if let earliest = try Date.fetchOne(
            db,
            sql: """
                SELECT MIN(\(ReadingEventRecord.Columns.occurredDate.name))
                FROM \(ReadingEventRecord.databaseTableName)
                WHERE \(ReadingEventRecord.Columns.seriesId.name) = ?
                """, arguments: [series.rawValue])
        {
            return earliest
        }

        let added = try SeriesRecord.fetchOne(db, key: series.rawValue)?.addedDate
        return added == .distantPast ? nil : added
    }
}

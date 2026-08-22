//
//  DetailsComposer+Tracking.swift
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
    final class Tracking: DetailsApplying, DetailsWriting {
        private(set) var links: [Link] = []

        // what a push would send - held here so a row can put the two numbers
        // side by side without asking the chapter list to recount them
        private(set) var furthest = 0

        private(set) var writing: Set<Tracker> = []

        var saving: Bool { !writing.isEmpty }
        private(set) var failure: Failure?

        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        // display title first, then every pooled one - a service files a work
        // under whichever name it knows, and a romaji title we display in
        // english is the most common near-miss
        @ObservationIgnored private var seriesTitles: [String] = []

        private let host: Compositor.Trackers
        private let database: DatabaseClient

        init(host: Compositor.Trackers, database: DatabaseClient) {
            self.host = host
            self.database = database
        }

        func apply(_ stored: Stored) {
            seriesId = stored.series.id

            let mapped = stored.trackers.compactMap { row -> Link? in
                guard let id = row.id else { return nil }

                return Link(
                    id: id.rawValue,
                    tracker: row.tracker,
                    remoteId: row.remoteId,
                    remoteTitle: row.remoteTitle,
                    status: row.remoteStatus,
                    progress: row.remoteProgress,
                    total: row.totalChapters,
                    score: row.remoteScore,
                    scoreFormat: format(for: row.tracker),
                    syncedDate: row.syncedDate,
                    attemptedDate: row.attemptedDate,
                    failureReason: row.syncError,
                    queued: row.pendingProgress != nil
                )
            }

            if links != mapped { links = mapped }
            if furthest != stored.furthest { furthest = stored.furthest }

            seriesTitles = [stored.entry.title] + stored.titles.map(\.value)
        }

        func clear() {
            failure = nil
        }

        // fixed order (Tracker.allCases), not host.accounts' own order, so the
        // rows never swap places
        var accounts: [Tracker] {
            Tracker.allCases.filter { host.accounts[$0] != nil }
        }

        // read from the credential, not an in-memory dead set, so it answers
        // the same on the launch after a token died as it did when it died
        var needingSignIn: Set<Tracker> {
            host.needingSignIn
        }

        var syncing: Set<Tracker> {
            guard let seriesId else { return [] }
            return host.syncing(series: seriesId.rawValue)
        }

        // a property of the account, not this series, so it is never stored
        // on the link row
        func format(for tracker: Tracker) -> ScoreFormat {
            tracker.fixedScoreFormat ?? host.accounts[tracker]?.scoreFormat ?? .point10
        }

        func search(
            _ tracker: Tracker,
            query: String,
            adult: Bool
        ) async throws -> [TrackerCandidate] {
            try await host.search(tracker, query: query, adult: adult)
        }

        // two rows pointing at one remote entry means both push their own
        // progress and each undoes the other, with nothing on the entry saying
        // which is winning - so the warning names the other series rather than
        // just flagging a clash
        func conflicts(_ tracker: Tracker) async -> [Int64: String] {
            await Self.conflicts(tracker, excluding: seriesId, in: database)
        }

        // static so the prefetch task can call it without capturing the
        // composer - a stored Task holding self is a retain cycle
        private static func conflicts(
            _ tracker: Tracker,
            excluding current: SeriesRecord.ID?,
            in database: DatabaseClient
        ) async -> [Int64: String] {
            (try? await database.reader.read { db -> [Int64: String] in
                let rows =
                    try SeriesTrackerRecord
                    .filter(SeriesTrackerRecord.Columns.tracker == tracker.rawValue)
                    .fetchAll(db)
                    .filter { $0.seriesId != current }

                guard !rows.isEmpty else { return [:] }

                let titles =
                    try RichfulEntryView
                    .filter(
                        rows.map(\.seriesId.rawValue).contains(RichfulEntryView.Columns.seriesId)
                    )
                    .fetchAll(db)
                    .reduce(into: [Int64: String]()) { out, entry in
                        out[entry.seriesId] = entry.title
                    }

                return rows.reduce(into: [Int64: String]()) { out, row in
                    out[row.remoteId] = titles[row.seriesId.rawValue] ?? "another series"
                }
            }) ?? [:]
        }

        // a service with no entry here is one that either was not searched or
        // whose search failed, and both render as the ordinary link row - a
        // failed search is not something the reader requested, so it is not
        // something they are told
        enum Match: Equatable {
            case searching
            case found(TrackerCandidate)
            case unmatched(count: Int)
        }

        private(set) var matches: [Tracker: Match] = [:]

        // kept whole so opening the link sheet costs nothing a second time -
        // the sheet awaits this same task, so tapping Search mid-flight waits
        // rather than starts a new one
        @ObservationIgnored private var searches: [Tracker: Task<Search, Never>] = [:]

        struct Search: Sendable {
            var results: [TrackerCandidate] = []
            var conflicts: [Int64: String] = [:]
            var failed = false
        }

        // only services that could still be linked - an account already
        // pointing at this series has nothing to search for, and searching it
        // would spend a request against anilist's budget to learn something
        // already on screen
        func prefetch(adult: Bool) {
            for tracker in accounts where searches[tracker] == nil {
                guard !links.contains(where: { $0.tracker == tracker }) else { continue }
                guard let query = seriesTitles.first, !query.isEmpty else { continue }

                matches[tracker] = .searching

                let search = Task { [host, database, current = seriesId] in
                    async let claimed = Self.conflicts(tracker, excluding: current, in: database)
                    guard let found = try? await host.search(tracker, query: query, adult: adult)
                    else {
                        return Search(failed: true)
                    }
                    return Search(results: found, conflicts: await claimed)
                }
                searches[tracker] = search

                let titles = seriesTitles
                Task { [weak self] in
                    let outcome = await search.value
                    guard let self else { return }
                    self.matches[tracker] = Self.match(outcome, against: titles)
                }
            }
        }

        // nil for a search that failed, so the row falls back rather than
        // reporting a miss it never actually established
        private static func match(_ outcome: Search, against titles: [String]) -> Match? {
            guard !outcome.failed else { return nil }

            // an entry another series already claims is not a candidate here -
            // the link sheet still offers it, dimmed, for the reader to pick
            // deliberately
            var exact = outcome.results.filter { candidate in
                outcome.conflicts[candidate.id] == nil
                    && titles.contains { Similarity.score($0, candidate.title) == 1 }
            }

            // a manga and its light novel share a title far more often than two
            // manga do, and linking the novel is the misfire TrackerCandidate
            // already names. anything still tied after that is a real ambiguity
            // and the reader decides it
            if exact.count > 1 { exact.removeAll(where: \.isNovel) }

            guard exact.count == 1, let only = exact.first else {
                return .unmatched(count: outcome.results.count)
            }
            return .found(only)
        }

        func prefetched(_ tracker: Tracker) async -> Search? {
            guard let task = searches[tracker] else { return nil }
            let outcome = await task.value
            return outcome.failed ? nil : outcome
        }

        // progress is never sent - this runs before the flow has asked a
        // single question, and the one thing it must not do is answer one on
        // the reader's behalf
        func autoLink(_ tracker: Tracker, candidate: TrackerCandidate) async {
            // marked before the entry read, not after - that read is a whole
            // network round trip, and link()'s own defer clears this either way
            writing.insert(tracker)
            defer { writing.remove(tracker) }

            do {
                let existing = try await entry(tracker, remoteId: candidate.id)
                let status = existing.status ?? .planning

                try await link(
                    candidate,
                    on: tracker,
                    update: TrackerUpdate(
                        remoteId: candidate.id,
                        entryId: existing.entryId,
                        status: status
                    ),
                    status: status
                )
                matches[tracker] = nil
            } catch {
                failure = Failure(error, fallback: "Couldn't Link")
            }
        }

        func resolve(_ text: String, on tracker: Tracker) async -> TrackerCandidate? {
            guard let id = tracker.remoteId(in: text) else { return nil }
            guard let entry = try? await host.entry(tracker, remoteId: id) else { return nil }

            return TrackerCandidate(
                id: entry.remoteId,
                title: entry.title,
                totalChapters: entry.totalChapters
            )
        }

        // fetched when the reader opens the entry, not for every search result
        // - fifty of those would be fifty requests against a budget of thirty
        // a minute
        func entry(_ tracker: Tracker, remoteId: Int64) async throws -> TrackerEntry {
            try await host.entry(tracker, remoteId: remoteId)
        }

        // throws rather than raising its own failure - the control that
        // started this reports on it, so it isn't told twice
        func link(
            _ candidate: TrackerCandidate,
            on tracker: Tracker,
            update: TrackerUpdate,
            status: Status
        ) async throws {
            guard let seriesId else { return }

            writing.insert(tracker)
            defer { writing.remove(tracker) }

            try await host.link(
                series: seriesId,
                tracker: tracker,
                candidate: candidate,
                status: update.status ?? status,
                update: update
            )
        }

        func unlink(_ link: Link, removeRemote: Bool) async {
            guard let row = try? await record(link) else { return }

            writing.insert(link.tracker)
            defer { writing.remove(link.tracker) }

            do {
                try await host.unlink(row, removeRemote: removeRemote)
            } catch {
                failure = Failure(error, fallback: "Couldn't Unlink")
            }
        }

        // the one caller allowed to lower a number, and the only path that may
        // write to an entry the service already calls finished
        func edit(_ link: Link, update: TrackerUpdate) async throws {
            guard let row = try await record(link) else { throw TrackerError.unavailable }

            writing.insert(link.tracker)
            defer { writing.remove(link.tracker) }

            try await host.edit(row, update: update)
        }

        // the queue kept every pending column, so this asks the walk to run now
        // rather than at its next wake - never a second way to push
        func retry(_ link: Link) async {
            guard let row = try? await record(link) else { return }
            host.retry(row)
        }

        // this app is further along, so every linked service is told - they are
        // all behind the same read state, and syncing one while leaving another
        // stale is how the two drift apart for good.
        //
        // enqueue only writes a link whose pending value beats what the service
        // holds, so one already at or past the number is left untouched
        func push() async {
            guard let seriesId else { return }

            do {
                try await database.writer.write { db in
                    try SeriesTrackerRecord.enqueue(for: seriesId, in: db)
                }
            } catch {
                failure = Failure(error, fallback: "Couldn't Sync")
                return
            }

            host.flush()
        }

        private func record(_ link: Link) async throws -> SeriesTrackerRecord? {
            try await database.reader.read { db in
                try SeriesTrackerRecord.fetchOne(db, key: link.id)
            }
        }
    }
}

// reuses the batch write rather than inventing a second way to record
// reading - the service the number came from is already at it and declines,
// while a sibling service that is behind is brought up
extension DetailsComposer {
    func catchUp(to link: Tracking.Link) async {
        await catchUp(to: link.progress)
    }

    func catchUp(to progress: Int) async {
        let numbers = chapters.chapters
            .map(\.number)
            .filter { $0 <= Double(progress) }

        await chapters.mark(read: true, numbers: numbers)
    }
}

extension DetailsComposer.Tracking {
    // holds what the service last told us, not what we believe - the two
    // disagree between finishing a chapter and the push landing
    struct Link: Identifiable, Hashable {
        let id: Int64
        let tracker: Tracker
        let remoteId: Int64
        let remoteTitle: String
        let status: Status?
        let progress: Int
        let total: Int?

        // stored as 0...100 whatever the account displays it as, so a missing
        // format is a drawing problem and never a data one
        let score: Int?
        let scoreFormat: ScoreFormat

        // the last time this row and the service agreed, in either direction -
        // a push landing, a pull on link, or a manual edit. distantPast means
        // it never has, which only a link that failed its own seeding can be
        let syncedDate: Date

        // when we last tried, whether or not it worked. stamped always, so the
        // pair says both "is it broken" and "how long has it been"
        let attemptedDate: Date
        let failureReason: String?

        // the row is carrying a number the drain has not delivered yet. the
        // remote figure is therefore already stale in a known direction, which
        // is the difference between "this service is behind" and "this service
        // is behind and something is on its way to fix that"
        let queued: Bool

        var url: URL? { tracker.url(for: remoteId) }

        var failing: Bool { failureReason != nil }

        // the service has heard less than we have read. one behind is the
        // ordinary state while a push is in flight, so only a bigger gap
        // counts as a disagreement worth offering to fix
        func behind(_ local: Int) -> Bool {
            local > progress + 1
        }

        // deliberately without the sync stamp - this string is built in
        // apply() and would go stale ("synced 6 secs ago" stays that way until
        // the next write). the stamp is a clock, so it belongs to a
        // TimelineView at the call site instead
        var summary: String {
            var parts: [String] = []
            parts.append(total.map { "\(progress) of \($0)" } ?? "\(progress) read")
            if let score, score > 0 { parts.append(scoreFormat.label(for: score)) }
            return parts.joined(separator: " · ")
        }

        // nil when the two have never agreed rather than "never" - a link that
        // failed its own seeding already carries the reason on its second line
        var synced: Date? {
            syncedDate > .distantPast ? syncedDate : nil
        }
    }
}

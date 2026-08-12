//
//  DetailsComposer+Tracking.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Tagged
import Observation

extension DetailsComposer {
    @MainActor
    @Observable
    final class Tracking: DetailsApplying, DetailsWriting {
        private(set) var links: [Link] = []

        // how far this app has you read, which is what a push would send. held
        // here so a row can put the two numbers side by side without asking
        // the chapter list to count them again
        private(set) var furthest = 0

        // which services are being written, so one row spins while the other
        // stays live
        private(set) var writing: Set<Tracker> = []

        // from DetailsWriting
        var saving: Bool { !writing.isEmpty }
        private(set) var failure: Failure?

        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        private let host: Compositor.Trackers
        private let database: DatabaseClient

        init(host: Compositor.Trackers, database: DatabaseClient) {
            self.host = host
            self.database = database
        }

        // from DetailsApplying
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
                    failureReason: row.syncError
                )
            }

            if links != mapped { links = mapped }
            if furthest != stored.furthest { furthest = stored.furthest }
        }

        // from DetailsWriting
        func clear() {
            failure = nil
        }

        // connected accounts, in a fixed order so the rows never swap places
        var accounts: [Tracker] {
            Tracker.allCases.filter { host.accounts[$0] != nil }
        }

        // connected but unable to push until the reader signs in again. read
        // from the credential rather than an in-memory dead set, so it answers
        // the same on the launch after a token died as it did when it died
        var needingSignIn: Set<Tracker> {
            host.needingSignIn
        }

        var syncing: Set<Tracker> {
            guard let seriesId else { return [] }
            return host.syncing(series: seriesId.rawValue)
        }

        // the account's own scale, or a sane default while signed out. it is a
        // property of the account rather than of this series, so it is never
        // stored on the link row
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

        // which remote entries on this service are already spoken for by a
        // DIFFERENT series in the library. two rows pointing at one entry means
        // both push their own progress and each keeps undoing the other, and
        // nothing on the entry says which is winning - so the warning has to
        // name the other series rather than just flagging a clash
        func conflicts(_ tracker: Tracker) async -> [Int64: String] {
            let current = seriesId

            return (try? await database.reader.read { db -> [Int64: String] in
                let rows = try SeriesTrackerRecord
                    .filter(SeriesTrackerRecord.Columns.tracker == tracker.rawValue)
                    .fetchAll(db)
                    .filter { $0.seriesId != current }

                guard !rows.isEmpty else { return [:] }

                let titles = try RichfulEntryView
                    .filter(rows.map(\.seriesId.rawValue).contains(RichfulEntryView.Columns.seriesId))
                    .fetchAll(db)
                    .reduce(into: [Int64: String]()) { out, entry in
                        out[entry.seriesId] = entry.title
                    }

                return rows.reduce(into: [Int64: String]()) { out, row in
                    out[row.remoteId] = titles[row.seriesId.rawValue] ?? "another series"
                }
            }) ?? [:]
        }

        // pasting a link is the escape hatch for what search cannot reach: a
        // title romanised differently everywhere, or an entry buried past fifty
        // results
        func resolve(_ text: String, on tracker: Tracker) async -> TrackerCandidate? {
            guard let id = tracker.remoteId(in: text) else { return nil }
            guard let entry = try? await host.entry(tracker, remoteId: id) else { return nil }

            return TrackerCandidate(
                id: entry.remoteId,
                title: entry.title,
                totalChapters: entry.totalChapters
            )
        }

        // what the reader's own list says about one entry, fetched when they
        // open it rather than for every search result - fifty of these would be
        // fifty requests against a budget of thirty a minute
        func entry(_ tracker: Tracker, remoteId: Int64) async throws -> TrackerEntry {
            try await host.entry(tracker, remoteId: remoteId)
        }

        // throws rather than raising its own failure: the control that started
        // this reports on it, and a second telling of one fact is the thing the
        // chapter-fetch path already learned to stop doing.
        //
        // status is passed in rather than read off the series - that lives on
        // another part of the composer, and a child never reaches sideways
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

// the remote is ahead and the reader said to accept it. it lives on the
// composer rather than on Tracking because catching up is a chapter mark - it
// reuses the batch write rather than inventing a second way to record reading,
// so the service the number came from is already at it and declines, while a
// sibling service that is behind is brought up
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
    // one service this series is linked to, holding what that service last
    // told us rather than what we believe - the two disagree between finishing
    // a chapter and the push landing
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

        var url: URL? { tracker.url(for: remoteId) }

        var failing: Bool { failureReason != nil }

        // the service has heard less than we have read. one behind is the
        // ordinary state while a push is in flight, so only a bigger gap
        // counts as a disagreement worth offering to fix
        func behind(_ local: Int) -> Bool {
            local > progress + 1
        }

        // progress, then score if it has one. deliberately WITHOUT the sync
        // stamp: this string is built in apply(), which runs when the database
        // changes, and "synced 6 secs ago" formatted there stays 6 secs ago
        // until something else writes. the stamp is a clock, so it belongs to a
        // TimelineView at the call site rather than to a string built once
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

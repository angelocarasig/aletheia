//
//  FailuresViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Observation
import Tagged

// what is failing right now, straight off origin.fetchError. observed rather
// than fetched once: the column is cleared the moment a source answers, so a
// successful retry has to take its own row off this screen without being told.
// see docs/features/background-activity.md 5.1
@MainActor
@Observable
final class FailuresViewModel {
    private let database: DatabaseClient
    private let registry: Compositor.Registry
    private let refresher: Compositor.Refresh
    private let trackers: Compositor.Trackers

    private(set) var entries: [Entry]?
    // the other half of the same question. kept apart from `entries` rather than
    // folded in: a source failure is a series on a source, a tracker failure is a
    // series on a service, and the grouping control below only makes sense for
    // the first pair
    private(set) var links: [TrackerEntry]?
    private(set) var failure: Failure?
    private(set) var retrying: Set<Int64> = []

    @ObservationIgnored private var stream: Task<Void, Never>?

    init(
        database: DatabaseClient,
        registry: Compositor.Registry,
        refresher: Compositor.Refresh,
        trackers: Compositor.Trackers
    ) {
        self.database = database
        self.registry = registry
        self.refresher = refresher
        self.trackers = trackers
    }

    var isEmpty: Bool {
        (entries?.isEmpty ?? true) && (links?.isEmpty ?? true)
    }

    func observe() {
        guard stream == nil else { return }

        stream = Task { [weak self, database] in
            // one observation over both tables: two would each re-render the
            // screen on the other's writes, and the screen has one empty state
            let observation =
                ValueObservation
                .tracking { db in
                    (origins: try Self.stored(in: db), links: try Self.links(in: db))
                }
                .removeDuplicates { $0 == $1 }

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.entries = stored.origins
                    self.links = stored.links
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Failures")
                AppLog.shared.log(
                    "failures observation failed - \(error)", level: .error, category: "activity")
            }
        }
    }

    // the push is still queued - a failure leaves the pending columns where they
    // are - so a retry is waking the drain rather than resending anything. the
    // dead-account mark comes off first, or the lane halts again on the way in
    func retry(_ entry: TrackerEntry) {
        trackers.retry(entry.tracker)
    }

    // one origin, through the same unit everything else uses - so a retry here
    // joins a library run already checking this origin rather than racing it
    func retry(_ entry: Entry) async {
        guard let source = registry.source(slug: entry.sourceSlug) else { return }
        guard !retrying.contains(entry.id) else { return }

        retrying.insert(entry.id)
        defer { retrying.remove(entry.id) }

        _ = await refresher.chapters(
            source: source,
            seriesSlug: entry.slug,
            originId: OriginRecord.ID(rawValue: entry.id)
        )
    }

    // a section's whole blast radius in one tap rather than one row at a time.
    // fanned out concurrently rather than awaited in sequence - each retry
    // already goes through the same host-gated refresher a library run does,
    // so the gate is what paces requests to a shared host, not this loop
    func retryAll(_ entries: [Entry]) async {
        await withTaskGroup(of: Void.self) { group in
            for entry in entries where !retrying.contains(entry.id) {
                group.addTask { await self.retry(entry) }
            }
        }
    }

    nonisolated private static func stored(in db: Database) throws -> [Entry] {
        let sql = """
            SELECT
                o.id AS id,
                o.\(OriginRecord.Columns.seriesId.name) AS seriesId,
                o.\(OriginRecord.Columns.slug.name) AS slug,
                o.\(OriginRecord.Columns.fetchError.name) AS reason,
                o.\(OriginRecord.Columns.fetchAttemptedDate.name) AS attemptedDate,
                e.\(EntryView.Columns.title.name) AS title,
                e.\(EntryView.Columns.cover.name) AS cover,
                e.\(EntryView.Columns.path.name) AS path,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(OriginRecord.databaseTableName) o
            JOIN \(EntryView.databaseTableName) e
              ON e.\(EntryView.Columns.seriesId.name) = o.\(OriginRecord.Columns.seriesId.name)
            JOIN \(SourceRecord.databaseTableName) src
              ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE o.\(OriginRecord.Columns.fetchError.name) IS NOT NULL
              AND e.\(EntryView.Columns.inLibrary.name) = 1
            ORDER BY o.\(OriginRecord.Columns.fetchAttemptedDate.name) DESC, o.id ASC
            """

        return try Entry.fetchAll(db, sql: sql)
    }

    nonisolated private static func links(in db: Database) throws -> [TrackerEntry] {
        let sql = """
            SELECT
                t.id AS id,
                t.\(SeriesTrackerRecord.Columns.seriesId.name) AS seriesId,
                t.\(SeriesTrackerRecord.Columns.tracker.name) AS tracker,
                t.\(SeriesTrackerRecord.Columns.remoteTitle.name) AS remoteTitle,
                t.\(SeriesTrackerRecord.Columns.syncError.name) AS reason,
                t.\(SeriesTrackerRecord.Columns.attemptedDate.name) AS attemptedDate,
                e.\(EntryView.Columns.title.name) AS title,
                e.\(EntryView.Columns.cover.name) AS cover,
                e.\(EntryView.Columns.path.name) AS path
            FROM \(SeriesTrackerRecord.databaseTableName) t
            JOIN \(EntryView.databaseTableName) e
              ON e.\(EntryView.Columns.seriesId.name) = t.\(SeriesTrackerRecord.Columns.seriesId.name)
            WHERE t.\(SeriesTrackerRecord.Columns.syncError.name) IS NOT NULL
              AND e.\(EntryView.Columns.inLibrary.name) = 1
            ORDER BY t.\(SeriesTrackerRecord.Columns.attemptedDate.name) DESC, t.id ASC
            """

        return try TrackerEntry.fetchAll(db, sql: sql)
    }
}

// MARK: - Grouping

extension FailuresViewModel {
    // the same failures read two ways. a source that died takes every series it
    // carried with it, so grouping by source answers "what broke"; a series
    // healthy on one source and dead on another is only visible grouped by
    // series, which answers "what am I missing"
    enum Grouping: String, CaseIterable, Identifiable {
        case source
        case series

        var id: String { rawValue }

        var label: String {
            switch self {
            case .source: "By Source"
            case .series: "By Series"
            }
        }
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let count: Int
        // the source's own icon where the section is a source; a series section
        // has no single icon to show, because its whole point is that several
        // sources disagree about it
        let sourceSlug: String?
        let entries: [Entry]
    }

    func sections(by grouping: Grouping) -> [Section] {
        let entries = entries ?? []

        switch grouping {
        case .source:
            return group(entries, by: \.sourceSlug) { slug, rows in
                Section(
                    id: slug,
                    title: rows[0].sourceName,
                    count: rows.count,
                    sourceSlug: slug,
                    entries: rows.sorted {
                        $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                )
            }

        case .series:
            return group(entries, by: { String($0.seriesId) }) { id, rows in
                Section(
                    id: id,
                    title: rows[0].title,
                    count: rows.count,
                    sourceSlug: nil,
                    entries: rows.sorted {
                        $0.sourceName.localizedStandardCompare($1.sourceName) == .orderedAscending
                    }
                )
            }
        }
    }

    // widest blast radius first, then alphabetical - a source taking six series
    // down is the thing to look at before one taking a single series
    private func group(
        _ entries: [Entry],
        by key: (Entry) -> String,
        into section: (String, [Entry]) -> Section
    ) -> [Section] {
        Dictionary(grouping: entries, by: key)
            .map { section($0.key, $0.value) }
            .sorted {
                guard $0.count == $1.count else { return $0.count > $1.count }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }
}

extension FailuresViewModel {
    struct Entry: Decodable, FetchableRecord, Identifiable, Equatable, Sendable {
        let id: Int64
        let seriesId: Int64
        let slug: String
        let reason: String
        let attemptedDate: Date
        let title: String
        // the remote URL and the downloaded file for the same cover - the local
        // one wins where it exists, so a failing source does not also mean a
        // missing thumbnail
        let cover: URL?
        let path: String?
        let sourceName: String
        let sourceSlug: String
    }

    // no per-link retry state: a retry wakes the whole lane, so spinning one row
    // while its siblings sat still would be drawing a distinction the engine does
    // not make
    struct TrackerEntry: Decodable, FetchableRecord, Identifiable, Equatable, Sendable {
        let id: Int64
        let seriesId: Int64
        let tracker: Tracker
        // what the service calls it, which is not always what we call it - and on
        // this screen the difference is worth seeing, since a wrong link is one
        // reason a push keeps failing
        let remoteTitle: String
        let reason: String
        let attemptedDate: Date
        let title: String
        let cover: URL?
        let path: String?
    }
}

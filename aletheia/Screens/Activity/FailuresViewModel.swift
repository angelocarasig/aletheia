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

@MainActor
@Observable
final class FailuresViewModel {
    private let database: DatabaseClient
    private let registry: Compositor.Registry
    private let refresher: Compositor.Refresh
    private let trackers: Compositor.Trackers

    private(set) var entries: [Entry]?
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
            // one observation over both tables - two would each re-render the screen on the other's writes
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

    // wakes the drain rather than resending - the dead-account mark must clear first or the lane halts again on the way in
    func retry(_ entry: TrackerEntry) {
        trackers.retry(entry.tracker)
    }

    // through the same fetch unit a library run uses, so this joins an already-running check rather than racing it
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

    // fanned out concurrently - HostGate paces requests to a shared host, not this loop
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
        let cover: URL?
        let path: String?
        let sourceName: String
        let sourceSlug: String
    }

    // no per-link retry state - a retry wakes the whole lane, not just this row, so there is nothing per-row to spin
    struct TrackerEntry: Decodable, FetchableRecord, Identifiable, Equatable, Sendable {
        let id: Int64
        let seriesId: Int64
        let tracker: Tracker
        let remoteTitle: String
        let reason: String
        let attemptedDate: Date
        let title: String
        let cover: URL?
        let path: String?
    }
}

//
//  ActivityStatsViewModel.swift
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
final class StatsViewModel {
    private let database: DatabaseClient

    private(set) var snapshot: Snapshot?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    private enum Rule {
        static let heatWeeks = 16
        static let sessionLimit = 20
        static let chartDays = 16 * 7
        static let chartLimit = 500
    }

    init(database: DatabaseClient) {
        self.database = database
    }

    func observe() {
        guard stream == nil else { return }
        let asOf = Date.now
        let heatKey =
            Calendar.current.date(
                byAdding: .weekOfYear, value: -(Rule.heatWeeks - 1), to: asOf
            )?.localDayKey ?? 0

        stream = Task { [weak self, database] in
            let observation =
                ValueObservation
                .tracking { db in
                    try Self.stored(asOf: asOf, heatKey: heatKey, in: db)
                }
                .removeDuplicates()

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.snapshot = stored
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Reading Activity")
                AppLog.shared.log(
                    "stats observation failed - \(error)", level: .error, category: "home")
            }
        }
    }

    func retry() {
        stream?.cancel()
        stream = nil
        failure = nil
        observe()
    }

    // MARK: Query

    // deliberately no adult gate: these are totals over what was actually read,
    // and filtering would make the streak and heatmap wrong, not just smaller
    nonisolated private static func stored(
        asOf: Date,
        heatKey: Int,
        in db: Database
    ) throws -> Snapshot {
        let chapters =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM \(ReadingEventRecord.databaseTableName)
                    WHERE \(ReadingEventRecord.Columns.kind.name) = ?
                    """,
                arguments: [ReadingEventRecord.Kind.chapterCompleted.rawValue]
            ) ?? 0

        let (seconds, pages) =
            try Row.fetchOne(
                db,
                sql: """
                    SELECT
                        IFNULL(SUM(
                            strftime('%s', \(ReadingSessionRecord.Columns.endedDate.name))
                            - strftime('%s', \(ReadingSessionRecord.Columns.startedDate.name))
                        ), 0) AS seconds,
                        IFNULL(SUM(\(ReadingSessionRecord.Columns.pagesRead.name)), 0) AS pages
                    FROM \(ReadingSessionRecord.databaseTableName)
                    """
            ).map { ($0["seconds"] as Int? ?? 0, $0["pages"] as Int? ?? 0) } ?? (0, 0)

        let days = try Int.fetchAll(
            db,
            sql: """
                SELECT DISTINCT \(ReadingEventRecord.Columns.localDayKey.name)
                FROM \(ReadingEventRecord.databaseTableName)
                UNION
                SELECT DISTINCT \(ReadingSessionRecord.Columns.localDayKey.name)
                FROM \(ReadingSessionRecord.databaseTableName)
                """
        )
        let daySet = Set(days)

        let heatRows = try Row.fetchAll(
            db,
            sql: """
                SELECT
                    \(ReadingSessionRecord.Columns.localDayKey.name) AS day,
                    IFNULL(SUM(\(ReadingSessionRecord.Columns.pagesRead.name)), 0) AS pages,
                    IFNULL(SUM(\(ReadingSessionRecord.Columns.chaptersRead.name)), 0) AS chapters
                FROM \(ReadingSessionRecord.databaseTableName)
                WHERE \(ReadingSessionRecord.Columns.localDayKey.name) >= ?
                GROUP BY day
                """,
            arguments: [heatKey]
        )
        let heat = Dictionary(
            uniqueKeysWithValues: heatRows.map {
                ($0["day"] as Int? ?? 0, $0["pages"] as Int? ?? 0)
            }
        )
        let heatChapters = Dictionary(
            uniqueKeysWithValues: heatRows.map {
                ($0["day"] as Int? ?? 0, $0["chapters"] as Int? ?? 0)
            }
        )

        let sessions = try ReadingSessionEntry.fetch(
            sinceKey: 0,
            excluded: [],
            limit: Rule.sessionLimit,
            in: db
        )

        let chartKey =
            Calendar.current.date(
                byAdding: .day, value: -(Rule.chartDays - 1), to: asOf
            )?.localDayKey ?? 0

        // fetched whole, not aggregated - chart buckets by interval intersection, needs both timestamps per sitting
        let recent = try ReadingSessionEntry.fetch(
            sinceKey: chartKey,
            excluded: [],
            limit: Rule.chartLimit,
            in: db
        )

        return Snapshot(
            chaptersAllTime: chapters,
            secondsAllTime: seconds,
            pagesAllTime: pages,
            currentRun: ReadingStreak.current(days: daySet, asOf: asOf),
            longestRun: ReadingStreak.longest(days: daySet),
            heat: heat,
            heatChapters: heatChapters,
            heatStartKey: heatKey,
            sessions: sessions,
            recent: recent
        )
    }
}

// MARK: - Snapshot

extension StatsViewModel {
    struct Snapshot: Equatable, Sendable {
        let chaptersAllTime: Int
        let secondsAllTime: Int
        let pagesAllTime: Int
        let currentRun: Int
        let longestRun: Int
        let heat: [Int: Int]
        let heatChapters: [Int: Int]
        let heatStartKey: Int

        func heat(for metric: ReadingMetric) -> [Int: Int] {
            switch metric {
            case .pages: heat
            case .chapters: heatChapters
            }
        }
        let sessions: [ReadingSessionEntry]
        let recent: [ReadingSessionEntry]

        var isEmpty: Bool {
            chaptersAllTime == 0 && secondsAllTime == 0 && sessions.isEmpty
        }
    }

}

// MARK: - Previews

#if DEBUG
    extension StatsViewModel {
        static func preview(snapshot: Snapshot? = nil, failure: Failure? = nil) -> StatsViewModel {
            let database = DatabaseClient.preview
            let model = StatsViewModel(database: database)
            model.snapshot = snapshot
            model.failure = failure
            return model
        }
    }
#endif

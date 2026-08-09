//
//  StatsViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation

@MainActor
@Observable
final class StatsViewModel {
    private let database: DatabaseClient
    private let registry: Compositor.Registry

    private(set) var snapshot: Snapshot?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    private enum Rule {
        static let heatWeeks = 16
        static let sessionLimit = 60
    }

    init(database: DatabaseClient, registry: Compositor.Registry) {
        self.database = database
        self.registry = registry
    }

    func observe() {
        guard stream == nil else { return }
        let asOf = Date.now
        let heatKey = Calendar.current.date(
            byAdding: .weekOfYear, value: -(Rule.heatWeeks - 1), to: asOf
        )?.localDayKey ?? 0

        let adultSlugs = UserDefaults.standard.bool(forKey: Preferences.Key.bypassAdultSources)
            ? []
            : registry.sources.filter(\.descriptor.adultOnly).map(\.descriptor.slug)

        stream = Task { [weak self, database] in
            let observation = ValueObservation
                .tracking { db in
                    try Self.stored(asOf: asOf, heatKey: heatKey, adultSlugs: adultSlugs, in: db)
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
                AppLog.shared.log("stats observation failed — \(error)", category: "home")
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

    nonisolated private static func stored(
        asOf: Date,
        heatKey: Int,
        adultSlugs: [String],
        in db: Database
    ) throws -> Snapshot {
        let excluded = try excludedSeries(adultSlugs: adultSlugs, in: db)
        let exclusion = excluded.isEmpty
            ? ""
            : "AND seriesId NOT IN (\(excluded.map(String.init).joined(separator: ", ")))"

        let chapters = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(ReadingEventRecord.databaseTableName)
                WHERE \(ReadingEventRecord.Columns.kind.name) = ? \(exclusion)
                """,
            arguments: [ReadingEventRecord.Kind.chapterCompleted.rawValue]
        ) ?? 0

        let (seconds, pages) = try Row.fetchOne(
            db,
            sql: """
                SELECT
                    IFNULL(SUM(
                        strftime('%s', \(ReadingSessionRecord.Columns.endedDate.name))
                        - strftime('%s', \(ReadingSessionRecord.Columns.startedDate.name))
                    ), 0) AS seconds,
                    IFNULL(SUM(\(ReadingSessionRecord.Columns.pagesRead.name)), 0) AS pages
                FROM \(ReadingSessionRecord.databaseTableName)
                WHERE 1 \(exclusion)
                """
        ).map { ($0["seconds"] as Int? ?? 0, $0["pages"] as Int? ?? 0) } ?? (0, 0)

        let days = try Int.fetchAll(
            db,
            sql: """
                SELECT DISTINCT \(ReadingEventRecord.Columns.localDayKey.name)
                FROM \(ReadingEventRecord.databaseTableName) WHERE 1 \(exclusion)
                UNION
                SELECT DISTINCT \(ReadingSessionRecord.Columns.localDayKey.name)
                FROM \(ReadingSessionRecord.databaseTableName) WHERE 1 \(exclusion)
                """
        )
        let daySet = Set(days)

        let heatRows = try Row.fetchAll(
            db,
            sql: """
                SELECT \(ReadingEventRecord.Columns.localDayKey.name) AS day, COUNT(*) AS count
                FROM \(ReadingEventRecord.databaseTableName)
                WHERE \(ReadingEventRecord.Columns.kind.name) = ?
                  AND \(ReadingEventRecord.Columns.localDayKey.name) >= ?
                  \(exclusion)
                GROUP BY day
                """,
            arguments: [ReadingEventRecord.Kind.chapterCompleted.rawValue, heatKey]
        )
        let heat = Dictionary(
            uniqueKeysWithValues: heatRows.map { ($0["day"] as Int? ?? 0, $0["count"] as Int? ?? 0) }
        )

        let sessions = try ReadingSessionEntry.fetch(
            sinceKey: 0,
            excluded: excluded,
            limit: Rule.sessionLimit,
            in: db
        )

        return Snapshot(
            chaptersAllTime: chapters,
            secondsAllTime: seconds,
            pagesAllTime: pages,
            currentRun: ReadingStreak.current(days: daySet, asOf: asOf),
            longestRun: ReadingStreak.longest(days: daySet),
            heat: heat,
            heatStartKey: heatKey,
            sessions: sessions
        )
    }

    nonisolated private static func excludedSeries(
        adultSlugs: [String],
        in db: Database
    ) throws -> Set<Int64> {
        guard !adultSlugs.isEmpty else { return [] }

        let marks = adultSlugs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT DISTINCT o.\(OriginRecord.Columns.seriesId.name)
            FROM \(OriginRecord.databaseTableName) o
            JOIN \(SourceRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE s.\(SourceRecord.Columns.slug.name) IN (\(marks))
            """
        return Set(try Int64.fetchAll(db, sql: sql, arguments: StatementArguments(adultSlugs)))
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
        let heatStartKey: Int
        let sessions: [ReadingSessionEntry]

        var isEmpty: Bool {
            chaptersAllTime == 0 && secondsAllTime == 0 && sessions.isEmpty
        }
    }

}

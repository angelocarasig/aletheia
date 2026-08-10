//
//  ActivityViewModel.swift
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
final class ActivityViewModel {
    private let database: DatabaseClient

    private(set) var snapshot: Snapshot?
    private(set) var failure: Failure?

    var grouping: Grouping = .day

    @ObservationIgnored private var stream: Task<Void, Never>?

    private enum Rule {
        static let window: TimeInterval = 30 * 24 * 60 * 60
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case day = "Days"
        case series = "Series"
        var id: String { rawValue }
    }

    init(database: DatabaseClient) {
        self.database = database
    }

    func observe() {
        guard stream == nil else { return }
        let asOf = Date.now
        let windowKey = asOf.addingTimeInterval(-Rule.window).localDayKey

        stream = Task { [weak self, database] in
            let observation = ValueObservation
                .tracking { db in
                    try Self.stored(windowKey: windowKey, in: db)
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
                self.failure = Failure(error, fallback: "Couldn't Load Activity")
                AppLog.shared.log("activity observation failed — \(error)", category: "activity")
            }
        }
    }

    func retry() {
        stream?.cancel()
        stream = nil
        failure = nil
        observe()
    }

    // MARK: Grouped output

    var days: [DayGroup] {
        guard let snapshot else { return [] }
        return Dictionary(grouping: snapshot.entries, by: \.localDayKey)
            .map { key, entries in
                DayGroup(day: key, entries: entries.sorted { $0.latestDate > $1.latestDate })
            }
            .sorted { $0.day > $1.day }
    }

    var series: [SeriesGroup] {
        guard let snapshot else { return [] }
        return Dictionary(grouping: snapshot.entries, by: \.seriesId)
            .compactMap { _, entries -> SeriesGroup? in
                guard let newest = entries.max(by: { $0.latestDate < $1.latestDate }) else { return nil }
                return SeriesGroup(
                    seriesId: newest.seriesId,
                    title: newest.title,
                    alive: newest.alive,
                    target: newest.target,
                    chapters: entries.reduce(0) { $0 + $1.chapters },
                    pages: entries.reduce(0) { $0 + $1.pages },
                    seconds: entries.reduce(0) { $0 + $1.seconds },
                    latestDate: newest.latestDate,
                    days: entries.count
                )
            }
            .sorted { $0.latestDate > $1.latestDate }
    }

    // MARK: Query

    // the feed's grain is one row per series per day, merged from both tables:
    // completions come from events (authoritative, and they survive a crashed
    // sitting), pages and time come from sessions. a union of keys keeps a
    // page-only sitting and a crash-orphaned completion both visible
    // no adult gate here, unlike Home and Library: this is the record of what you
    // read, and a feed that silently drops days is a feed that cannot be trusted
    // about the days it does show
    nonisolated private static func stored(
        windowKey: Int,
        in db: Database
    ) throws -> Snapshot {
        struct EventGroup: Decodable, FetchableRecord {
            let localDayKey: Int
            let seriesId: Int64
            let seriesTitle: String
            let chapters: Int
            let latestDate: Date
        }

        let eventGroups = try EventGroup.fetchAll(
            db,
            sql: """
                SELECT
                    \(ReadingEventRecord.Columns.localDayKey.name) AS localDayKey,
                    \(ReadingEventRecord.Columns.seriesId.name) AS seriesId,
                    MAX(\(ReadingEventRecord.Columns.seriesTitle.name)) AS seriesTitle,
                    COUNT(*) AS chapters,
                    MAX(\(ReadingEventRecord.Columns.occurredDate.name)) AS latestDate
                FROM \(ReadingEventRecord.databaseTableName)
                WHERE \(ReadingEventRecord.Columns.kind.name) = ?
                  AND \(ReadingEventRecord.Columns.localDayKey.name) >= ?
                GROUP BY localDayKey, seriesId
                """,
            arguments: [ReadingEventRecord.Kind.chapterCompleted.rawValue, windowKey]
        )

        struct SessionGroup: Decodable, FetchableRecord {
            let localDayKey: Int
            let seriesId: Int64
            let seriesTitle: String
            let pages: Int
            let seconds: Int
            let latestDate: Date
        }

        let sessionGroups = try SessionGroup.fetchAll(
            db,
            sql: """
                SELECT
                    \(ReadingSessionRecord.Columns.localDayKey.name) AS localDayKey,
                    \(ReadingSessionRecord.Columns.seriesId.name) AS seriesId,
                    MAX(\(ReadingSessionRecord.Columns.seriesTitle.name)) AS seriesTitle,
                    IFNULL(SUM(\(ReadingSessionRecord.Columns.pagesRead.name)), 0) AS pages,
                    IFNULL(SUM(
                        strftime('%s', \(ReadingSessionRecord.Columns.endedDate.name))
                        - strftime('%s', \(ReadingSessionRecord.Columns.startedDate.name))
                    ), 0) AS seconds,
                    MAX(\(ReadingSessionRecord.Columns.endedDate.name)) AS latestDate
                FROM \(ReadingSessionRecord.databaseTableName)
                WHERE \(ReadingSessionRecord.Columns.localDayKey.name) >= ?
                GROUP BY localDayKey, seriesId
                """,
            arguments: [windowKey]
        )

        struct Key: Hashable { let day: Int; let series: Int64 }
        var merged: [Key: FeedEntry] = [:]

        for group in eventGroups {
            let key = Key(day: group.localDayKey, series: group.seriesId)
            merged[key] = FeedEntry(
                localDayKey: group.localDayKey,
                seriesId: group.seriesId,
                title: group.seriesTitle,
                alive: false,
                target: nil,
                chapters: group.chapters,
                pages: 0,
                seconds: 0,
                latestDate: group.latestDate
            )
        }

        for group in sessionGroups {
            let key = Key(day: group.localDayKey, series: group.seriesId)
            if var entry = merged[key] {
                entry.pages = group.pages
                entry.seconds = group.seconds
                entry.latestDate = max(entry.latestDate, group.latestDate)
                merged[key] = entry
            } else {
                merged[key] = FeedEntry(
                    localDayKey: group.localDayKey,
                    seriesId: group.seriesId,
                    title: group.seriesTitle,
                    alive: false,
                    target: nil,
                    chapters: 0,
                    pages: group.pages,
                    seconds: group.seconds,
                    latestDate: group.latestDate
                )
            }
        }

        // soft joins after the merge: which snapshots still point at a live
        // series, and where "keep reading" would land for those that do
        let seriesIds = Array(Set(merged.values.map(\.seriesId)))
        let alive = try aliveSeries(seriesIds, in: db)
        let targets = try ContinueTarget.resolve(for: seriesIds.filter(alive.contains), in: db)

        let entries = merged.values.map { entry in
            var entry = entry
            entry.alive = alive.contains(entry.seriesId)
            entry.target = targets[entry.seriesId]
            return entry
        }

        // the idle facts the Now section settles to. .distantPast is the
        // never-fetched sentinel, which reads as "not checked yet"
        let lastChecked = try Date.fetchOne(
            db,
            sql: """
                SELECT MAX(o.\(OriginRecord.Columns.chaptersFetchedDate.name))
                FROM \(OriginRecord.databaseTableName) o
                JOIN \(SeriesRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.seriesId.name)
                WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1
                """
        ).flatMap { $0 > Date(timeIntervalSince1970: 0) ? $0 : nil }

        let downloadedChapters = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(ChapterRecord.databaseTableName)
                WHERE \(ChapterRecord.Columns.path.name) IS NOT NULL
                """
        ) ?? 0

        // currently failing, not ever failed: the column is cleared the moment a
        // source answers again, so this needs no acknowledgement state of its own
        let failingSources = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(OriginRecord.databaseTableName) o
                JOIN \(SeriesRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.seriesId.name)
                WHERE o.\(OriginRecord.Columns.fetchError.name) IS NOT NULL
                  AND s.\(SeriesRecord.Columns.inLibrary.name) = 1
                """
        ) ?? 0

        return Snapshot(
            entries: entries.sorted { $0.latestDate > $1.latestDate },
            lastChecked: lastChecked,
            downloadedChapters: downloadedChapters,
            failingSources: failingSources
        )
    }

    nonisolated private static func aliveSeries(_ ids: [Int64], in db: Database) throws -> Set<Int64> {
        guard !ids.isEmpty else { return [] }
        let marks = ids.map { _ in "?" }.joined(separator: ", ")
        return Set(try Int64.fetchAll(
            db,
            sql: "SELECT id FROM \(SeriesRecord.databaseTableName) WHERE id IN (\(marks))",
            arguments: StatementArguments(ids)
        ))
    }

}

// MARK: - Snapshot

extension ActivityViewModel {
    struct Snapshot: Equatable, Sendable {
        let entries: [FeedEntry]
        let lastChecked: Date?
        let downloadedChapters: Int
        let failingSources: Int
        var isEmpty: Bool { entries.isEmpty }
    }

    struct FeedEntry: Identifiable, Hashable, Sendable {
        let localDayKey: Int
        let seriesId: Int64
        let title: String
        var alive: Bool
        var target: ContinueTarget?
        var chapters: Int
        var pages: Int
        var seconds: Int
        var latestDate: Date

        var id: String { "\(localDayKey)-\(seriesId)" }
    }

    struct DayGroup: Identifiable {
        let day: Int
        let entries: [FeedEntry]
        var id: Int { day }
    }

    struct SeriesGroup: Identifiable {
        let seriesId: Int64
        let title: String
        let alive: Bool
        let target: ContinueTarget?
        let chapters: Int
        let pages: Int
        let seconds: Int
        let latestDate: Date
        let days: Int
        var id: Int64 { seriesId }
    }
}

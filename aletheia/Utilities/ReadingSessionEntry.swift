//
//  ReadingSessionEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB

// one sitting, as any screen wants to show it. the query lives here rather than
// in a view model because Home and the stats drill-down ask the same question
// of the same table and differ only in how far back and how many
struct ReadingSessionEntry: Identifiable, Hashable, Decodable, FetchableRecord, Sendable {
    let id: Int64
    let seriesId: Int64
    let seriesTitle: String
    let pagesRead: Int
    let chaptersRead: Int
    let startedDate: Date
    let endedDate: Date
    let localDayKey: Int
    // whether the snapshot still points at a live series row - a merged or
    // removed series keeps its history but loses its navigation
    let alive: Bool

    var seconds: Int {
        Int(endedDate.timeIntervalSince(startedDate))
    }

    static func fetch(
        sinceKey: Int,
        excluded: Set<Int64>,
        limit: Int,
        in db: Database
    ) throws -> [ReadingSessionEntry] {
        let exclusion = excluded.isEmpty
            ? ""
            : "AND rs.\(ReadingSessionRecord.Columns.seriesId.name) NOT IN (\(excluded.map(String.init).joined(separator: ", ")))"

        return try ReadingSessionEntry.fetchAll(
            db,
            sql: """
                SELECT
                    rs.id AS id,
                    rs.\(ReadingSessionRecord.Columns.seriesId.name) AS seriesId,
                    rs.\(ReadingSessionRecord.Columns.seriesTitle.name) AS seriesTitle,
                    rs.\(ReadingSessionRecord.Columns.pagesRead.name) AS pagesRead,
                    rs.\(ReadingSessionRecord.Columns.chaptersRead.name) AS chaptersRead,
                    rs.\(ReadingSessionRecord.Columns.startedDate.name) AS startedDate,
                    rs.\(ReadingSessionRecord.Columns.endedDate.name) AS endedDate,
                    rs.\(ReadingSessionRecord.Columns.localDayKey.name) AS localDayKey,
                    (s.id IS NOT NULL) AS alive
                FROM \(ReadingSessionRecord.databaseTableName) rs
                LEFT JOIN \(SeriesRecord.databaseTableName) s ON s.id = rs.\(ReadingSessionRecord.Columns.seriesId.name)
                WHERE rs.\(ReadingSessionRecord.Columns.localDayKey.name) >= ?
                  \(exclusion)
                ORDER BY rs.\(ReadingSessionRecord.Columns.startedDate.name) DESC
                LIMIT \(limit)
                """,
            arguments: [sinceKey]
        )
    }
}

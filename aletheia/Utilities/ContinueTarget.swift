//
//  ContinueTarget.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged

// which chapter "keep reading" opens, per series: the partially-read chapter
// touched most recently wins, else the lowest-numbered unread one. a series
// with neither is finished and has no target. resuming a partway chapter and
// starting the next unread one are different intents, so the case says which
enum ContinueTarget: Hashable, Sendable {
    case resume(chapterId: ChapterRecord.ID, number: Double, progress: Double)
    case start(chapterId: ChapterRecord.ID, number: Double)

    var chapterId: ChapterRecord.ID {
        switch self {
        case let .resume(id, _, _), let .start(id, _): id
        }
    }

    var number: Double {
        switch self {
        case let .resume(_, number, _), let .start(_, number): number
        }
    }

    private struct Row: Decodable, FetchableRecord, Sendable {
        let seriesId: Int64
        let chapterId: Int64
        let number: Double
        let progress: Double
        let lastReadDate: Date?
    }

    static func resolve(for seriesIds: [Int64], in db: Database) throws -> [Int64: ContinueTarget] {
        guard !seriesIds.isEmpty else { return [:] }

        let marks = seriesIds.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT
                bc.seriesId AS seriesId,
                bc.chapterId AS chapterId,
                bc.number AS number,
                c.\(ChapterRecord.Columns.progress.name) AS progress,
                c.\(ChapterRecord.Columns.lastReadDate.name) AS lastReadDate
            FROM \(BestChapterView.databaseTableName) bc
            JOIN \(ChapterRecord.databaseTableName) c ON c.id = bc.chapterId
            WHERE bc.seriesId IN (\(marks))
              AND bc.rank = 1
              AND bc.isVisible = 1
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(seriesIds))

        return Dictionary(grouping: rows, by: \.seriesId).compactMapValues { chapters in
            if let partial = chapters
                .filter({ $0.progress > 0 && $0.progress < 1 })
                .max(by: { ($0.lastReadDate ?? .distantPast) < ($1.lastReadDate ?? .distantPast) }) {
                return .resume(
                    chapterId: ChapterRecord.ID(rawValue: partial.chapterId),
                    number: partial.number,
                    progress: partial.progress
                )
            }
            if let next = chapters
                .filter({ $0.progress < 1 })
                .min(by: { $0.number < $1.number }) {
                return .start(
                    chapterId: ChapterRecord.ID(rawValue: next.chapterId),
                    number: next.number
                )
            }
            return nil
        }
    }
}

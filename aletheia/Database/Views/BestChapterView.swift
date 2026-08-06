//
//  BestChapterView.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import GRDB

/// Pre-calculates the "best" chapter for each chapter number per series based on priority rules.
///
/// This view solves the deduplication problem where multiple sources/scanlators
/// provide the same chapter. It ranks chapters using:
/// 1. Origin priority (lower = better)
/// 2. Scanlator priority within that origin (lower = better)
///
/// Example:
/// - Series X has Chapter 1 from:
///   - Origin A (priority: 0) with Scanlator Y (priority: 0) → rank = 1 ✓ BEST
///   - Origin A (priority: 0) with Scanlator Z (priority: 1) → rank = 2
///   - Origin B (priority: 1) with Scanlator Y (priority: 0) → rank = 3
internal struct BestChapterView: ViewRecord {
    let chapterId: Int64
    let number: Double
    let progress: Double
    let seriesId: Int64
    let showHalfChapters: Bool
    let showAllChapters: Bool
    let isVisible: Bool
    let rank: Int
}

// MARK: - ViewRecord

extension BestChapterView {
    static var databaseTableName: String {
        "best_chapter"
    }

    static let dependsOn: [any DatabaseRecord.Type] = [
        ChapterRecord.self,
        OriginRecord.self,
        OriginScanlatorPriorityRecord.self,
        SeriesRecord.self,
        SourceRecord.self
    ]

    static var viewDefinition: SQLRequest<BestChapterView> {
        SQLRequest(sql: """
            SELECT
                c.id as chapterId,
                c.number,
                c.progress,
                o.seriesId,
                m.showHalfChapters,
                m.showAllChapters,
                -- compute visibility based on half-chapter filtering rules
                -- isVisible = 1 means this chapter should be shown to the user
                CASE
                    WHEN m.showAllChapters = 1 THEN 1
                    WHEN m.showHalfChapters = 1 THEN 1
                    WHEN c.number = CAST(c.number AS INTEGER) THEN 1
                    ELSE 0
                END as isVisible,
                -- rank chapters within each series/number combination
                -- rank = 1 means this is the best source for this chapter number
                ROW_NUMBER() OVER (
                    PARTITION BY o.seriesId, c.number
                    ORDER BY
                        o.priority ASC,  -- first: origin priority (0 is best)
                        COALESCE(osp.priority, 999) ASC,  -- then: scanlator priority (null treated as worst)
                        o.id ASC,  -- deterministic tiebreak - priorities are no longer unique
                        c.id ASC
                ) as rank
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON c.originId = o.id
            LEFT JOIN \(OriginScanlatorPriorityRecord.databaseTableName) osp
                ON osp.originId = o.id
                AND osp.scanlatorId = c.scanlatorId
            JOIN \(SeriesRecord.databaseTableName) m ON o.seriesId = m.id
            -- an unavailable source's chapters are unreadable, so they are excluded
            -- entirely rather than winning rank 1 and dead-ending the reader.
            -- the inner join drops disconnected origins (null sourceId) and the
            -- filter drops disabled ones - both are unavailable in the same way
            JOIN \(SourceRecord.databaseTableName) src ON o.sourceId = src.id
            WHERE src.\(SourceRecord.Columns.disabled.name) = 0
            """)
    }

    static func createIndexes(db: Database) throws {
        // optimize the window function partitioning and ordering
        try db.create(
            index: "idx_chapter_origin_scanlator_priority",
            on: ChapterRecord.databaseTableName,
            columns: [
                ChapterRecord.Columns.originId.name,
                ChapterRecord.Columns.number.name,
                ChapterRecord.Columns.progress.name
            ],
            ifNotExists: true
        )

        // optimize the scanlator priority join
        try db.create(
            index: "idx_origin_scanlator_priority_covering",
            on: OriginScanlatorPriorityRecord.databaseTableName,
            columns: [
                OriginScanlatorPriorityRecord.Columns.originId.name,
                OriginScanlatorPriorityRecord.Columns.scanlatorId.name,
                OriginScanlatorPriorityRecord.Columns.priority.name
            ],
            ifNotExists: true
        )
    }
}

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
/// 1. Language priority for the series (lower = better, unranked = worst)
/// 2. Origin priority (lower = better)
/// 3. Scanlator priority within that origin (lower = better)
///
/// Example:
/// - Series X (language priority: EN 0) has Chapter 1 from:
///   - Origin B (priority: 1) in EN with Scanlator Y → rank = 1 ✓ BEST
///   - Origin A (priority: 0) in JA with Scanlator Y (priority: 0) → rank = 2
///   - Origin A (priority: 0) in JA with Scanlator Z (priority: 1) → rank = 3
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
        SeriesLanguagePriorityRecord.self,
        SeriesRecord.self,
        SourceRecord.self,
    ]

    static var viewDefinition: SQLRequest<BestChapterView> {
        SQLRequest(
            sql: """
                SELECT
                    c.id as chapterId,
                    c.number,
                    c.progress,
                    o.seriesId,
                    m.showHalfChapters,
                    m.showAllChapters,
                    -- isVisible = 1 means this chapter should be shown to the user
                    CASE
                        WHEN m.showAllChapters = 1 THEN 1
                        WHEN m.showHalfChapters = 1 THEN 1
                        WHEN c.number = CAST(c.number AS INTEGER) THEN 1
                        ELSE 0
                    END as isVisible,
                    -- rank = 1 means this is the best source for this chapter number
                    ROW_NUMBER() OVER (
                        PARTITION BY o.seriesId, c.number
                        ORDER BY
                            -- language outranks origin deliberately - see
                            -- SeriesLanguagePriorityRecord
                            COALESCE(slp.priority, 999) ASC,  -- first: language priority (null treated as worst)
                            o.priority ASC,  -- then: origin priority (0 is best)
                            COALESCE(osp.priority, 999) ASC,  -- then: scanlator priority (null treated as worst)
                            o.id ASC,  -- deterministic tiebreak - priorities are no longer unique
                            c.id ASC
                    ) as rank
                FROM \(ChapterRecord.databaseTableName) c
                JOIN \(OriginRecord.databaseTableName) o ON c.originId = o.id
                LEFT JOIN \(OriginScanlatorPriorityRecord.databaseTableName) osp
                    ON osp.originId = o.id
                    AND osp.scanlatorId = c.scanlatorId
                -- left joined so an unranked language sorts last rather than dropping
                -- the chapter. a series with no rows here ranks exactly as before
                LEFT JOIN \(SeriesLanguagePriorityRecord.databaseTableName) slp
                    ON slp.\(SeriesLanguagePriorityRecord.Columns.seriesId.name) = o.seriesId
                    AND slp.\(SeriesLanguagePriorityRecord.Columns.language.name) = c.\(ChapterRecord.Columns.language.name)
                JOIN \(SeriesRecord.databaseTableName) m ON o.seriesId = m.id
                -- a chapter earns its place by being readable, which is two different
                -- things. either its source can still answer for it - not turned off
                -- by the reader, still shipped with the app, still attached to the
                -- origin - or its bytes are already on disk, in which case no source
                -- is needed at all and one being gone changes nothing.
                --
                -- left joined on purpose: an inner join drops a disconnected origin
                -- (null sourceId) before the filter can spare a downloaded chapter.
                -- ranking is deliberately untouched - a download only outranks a live
                -- copy when its origin already did, which is the reader's own ordering
                LEFT JOIN \(SourceRecord.databaseTableName) src ON o.sourceId = src.id
                WHERE (
                    (
                        src.id IS NOT NULL
                        AND src.\(SourceRecord.Columns.disabled.name) = 0
                        AND src.\(SourceRecord.Columns.installed.name) = 1
                    )
                    OR c.\(ChapterRecord.Columns.path.name) IS NOT NULL
                )
                """)
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_chapter_origin_scanlator_priority",
            on: ChapterRecord.databaseTableName,
            columns: [
                ChapterRecord.Columns.originId.name,
                ChapterRecord.Columns.number.name,
                ChapterRecord.Columns.progress.name,
            ],
            ifNotExists: true
        )

        try db.create(
            index: "idx_origin_scanlator_priority_covering",
            on: OriginScanlatorPriorityRecord.databaseTableName,
            columns: [
                OriginScanlatorPriorityRecord.Columns.originId.name,
                OriginScanlatorPriorityRecord.Columns.scanlatorId.name,
                OriginScanlatorPriorityRecord.Columns.priority.name,
            ],
            ifNotExists: true
        )
    }
}

//
//  EntryView.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB

internal struct EntryView: ViewRecord {
    let seriesId: Int64
    let sourceId: Int64?
    let slug: String
    let title: String
    let cover: URL?
    // the displayed cover's downloaded location, container-relative
    let path: String?
    let inLibrary: Bool
    let status: Status
    // resolved from the preferred metadata origin, else the primary one. nil only
    // when the series has no origins at all
    let classification: Classification?
    let publication: Publication?
    let unreadCount: Int

    let addedDate: Date
    let updatedDate: Date
    let lastReadDate: Date
    let lastFetchedDate: Date
}

// MARK: - ViewRecord

extension EntryView {
    static var databaseTableName: String {
        "entry_view"
    }

    enum Columns {
        static let seriesId = Column(CodingKeys.seriesId)
        static let sourceId = Column(CodingKeys.sourceId)
        static let slug = Column(CodingKeys.slug)
        static let title = Column(CodingKeys.title)
        static let cover = Column(CodingKeys.cover)
        static let path = Column(CodingKeys.path)
        static let inLibrary = Column(CodingKeys.inLibrary)
        static let status = Column(CodingKeys.status)
        static let classification = Column(CodingKeys.classification)
        static let publication = Column(CodingKeys.publication)
        static let unreadCount = Column(CodingKeys.unreadCount)
        static let addedDate = Column(CodingKeys.addedDate)
        static let updatedDate = Column(CodingKeys.updatedDate)
        static let lastReadDate = Column(CodingKeys.lastReadDate)
        static let lastFetchedDate = Column(CodingKeys.lastFetchedDate)
    }

    static let dependsOn: [any DatabaseRecord.Type] = [
        SeriesRecord.self,
        OriginRecord.self,
        SourceRecord.self,
        MetadataRecord.self,
        CoverRecord.self,
        TitleRecord.self,
    ]

    static let dependsOnViews: [any ViewRecord.Type] = [
        BestChapterView.self
    ]

    static var viewDefinition: SQLRequest<EntryView> {
        SQLRequest(
            sql: """
                SELECT
                    m.id as seriesId,
                    po.sourceId as sourceId,
                    COALESCE(po.slug, '') as slug,

                    -- title: the user's pick, else what the primary origin calls it,
                    -- else any title in the pool
                    COALESCE(
                        (SELECT t.\(TitleRecord.Columns.value.name)
                         FROM \(TitleRecord.databaseTableName) t
                         WHERE t.id = m.\(SeriesRecord.Columns.preferredTitleId.name)),
                        (SELECT t.\(TitleRecord.Columns.value.name)
                         FROM \(TitleRecord.databaseTableName) t
                         WHERE t.seriesId = m.id AND t.\(TitleRecord.Columns.metadataId.name) = pm.id
                         ORDER BY t.id ASC LIMIT 1),
                        (SELECT t.\(TitleRecord.Columns.value.name)
                         FROM \(TitleRecord.databaseTableName) t
                         WHERE t.seriesId = m.id
                         ORDER BY t.id ASC LIMIT 1),
                        ''
                    ) as title,

                    -- cover: same resolution order as title. resolved by joining the
                    -- row itself rather than selecting each column separately, so the
                    -- downloaded path can never belong to a different cover than the url
                    pc.\(CoverRecord.Columns.url.name) as cover,
                    pc.\(CoverRecord.Columns.path.name) as path,

                    m.inLibrary,
                    m.\(SeriesRecord.Columns.status.name) as status,

                    -- one pick each, else whatever the primary origin says - see
                    -- SeriesRecord.preferredClassificationId/preferredPublicationId
                    mc.\(MetadataRecord.Columns.classification.name) as classification,
                    mp.\(MetadataRecord.Columns.publication.name) as publication,

                    COALESCE(
                        (SELECT COUNT(*)
                         FROM \(BestChapterView.databaseTableName) bc
                         WHERE bc.seriesId = m.id
                           AND bc.rank = 1  -- only best version of each chapter
                           AND bc.progress < 1.0  -- unread
                           AND (bc.showHalfChapters = 1 OR bc.number = CAST(bc.number AS INTEGER))
                        ), 0
                    ) as unreadCount,

                    m.addedDate,
                    m.updatedDate,
                    m.lastReadDate,
                    m.lastFetchedDate

                FROM \(SeriesRecord.databaseTableName) m

                -- primary origin: available sources first, then by priority.
                -- unavailable means disconnected (null sourceId) or disabled - both
                -- sort last so a dead source stops supplying the displayed metadata.
                -- matched on id so ties never duplicate the row.
                LEFT JOIN \(OriginRecord.databaseTableName) po
                    ON po.id = (
                        SELECT o2.id
                        FROM \(OriginRecord.databaseTableName) o2
                        LEFT JOIN \(SourceRecord.databaseTableName) s2 ON o2.sourceId = s2.id
                        WHERE o2.seriesId = m.id
                        ORDER BY
                            (s2.id IS NULL OR s2.\(SourceRecord.Columns.disabled.name) = 1) ASC,
                            o2.priority ASC,
                            o2.id ASC
                        LIMIT 1
                    )

                -- the primary origin's own metadata row - at most one, since
                -- metadata is unique per supplier
                LEFT JOIN \(MetadataRecord.databaseTableName) pm
                    ON pm.\(MetadataRecord.Columns.originId.name) = po.id

                -- matched on id, so a pin left over from a deleted metadata row falls
                -- back to the primary origin rather than dropping the series
                LEFT JOIN \(MetadataRecord.databaseTableName) mc
                    ON mc.id = COALESCE(
                        m.\(SeriesRecord.Columns.preferredClassificationId.name),
                        pm.id
                    )

                LEFT JOIN \(MetadataRecord.databaseTableName) mp
                    ON mp.id = COALESCE(
                        m.\(SeriesRecord.Columns.preferredPublicationId.name),
                        pm.id
                    )

                -- the displayed cover: the user's pick, else the primary origin's
                -- first, else any
                LEFT JOIN \(CoverRecord.databaseTableName) pc
                    ON pc.id = COALESCE(
                        m.\(SeriesRecord.Columns.preferredCoverId.name),
                        (SELECT c.id FROM \(CoverRecord.databaseTableName) c
                         WHERE c.seriesId = m.id AND c.\(CoverRecord.Columns.metadataId.name) = pm.id
                         ORDER BY c.id ASC LIMIT 1),
                        (SELECT c.id FROM \(CoverRecord.databaseTableName) c
                         WHERE c.seriesId = m.id
                         ORDER BY c.id ASC LIMIT 1)
                    )
                """)
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_cover_seriesId_metadataId_id",
            on: CoverRecord.databaseTableName,
            columns: [
                CoverRecord.Columns.seriesId.name,
                CoverRecord.Columns.metadataId.name,
                CoverRecord.Columns.id.name,
            ],
            ifNotExists: true
        )

        try db.create(
            index: "idx_title_seriesId_metadataId_id",
            on: TitleRecord.databaseTableName,
            columns: [
                TitleRecord.Columns.seriesId.name,
                TitleRecord.Columns.metadataId.name,
                TitleRecord.Columns.id.name,
            ],
            ifNotExists: true
        )

        try db.create(
            index: "idx_origin_series_priority_covering",
            on: OriginRecord.databaseTableName,
            columns: [
                OriginRecord.Columns.seriesId.name,
                OriginRecord.Columns.priority.name,
                OriginRecord.Columns.sourceId.name,
                OriginRecord.Columns.slug.name,
            ],
            ifNotExists: true
        )
    }
}

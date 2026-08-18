//
//  RichfulEntryView.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB

internal struct RichfulEntryView: ViewRecord {
    let seriesId: Int64
    let sourceId: Int64?
    let slug: String
    let title: String
    let cover: URL?
    // the displayed cover's downloaded location, container-relative
    let path: String?
    let inLibrary: Bool
    let unreadCount: Int

    let authors: String?
    let synopsis: String?
    let tags: String?

    // resolved from the preferred metadata origin
    let classification: Classification?
    let publication: Publication?

    let addedDate: Date
    let updatedDate: Date
    let lastReadDate: Date
    let lastFetchedDate: Date

    let lastReadChapterNumber: Double?
    let totalChapterCount: Int
    let readChapterCount: Int
}

// MARK: - ViewRecord

extension RichfulEntryView {
    static var databaseTableName: String {
        "richful_entry_view"
    }

    enum Columns {
        static let seriesId = Column(CodingKeys.seriesId)
        static let sourceId = Column(CodingKeys.sourceId)
        static let slug = Column(CodingKeys.slug)
        static let title = Column(CodingKeys.title)
        static let cover = Column(CodingKeys.cover)
        static let path = Column(CodingKeys.path)
        static let inLibrary = Column(CodingKeys.inLibrary)
        static let unreadCount = Column(CodingKeys.unreadCount)
        static let authors = Column(CodingKeys.authors)
        static let synopsis = Column(CodingKeys.synopsis)
        static let tags = Column(CodingKeys.tags)
        static let classification = Column(CodingKeys.classification)
        static let publication = Column(CodingKeys.publication)
        static let addedDate = Column(CodingKeys.addedDate)
        static let updatedDate = Column(CodingKeys.updatedDate)
        static let lastReadDate = Column(CodingKeys.lastReadDate)
        static let lastFetchedDate = Column(CodingKeys.lastFetchedDate)
        static let lastReadChapterNumber = Column(CodingKeys.lastReadChapterNumber)
        static let totalChapterCount = Column(CodingKeys.totalChapterCount)
        static let readChapterCount = Column(CodingKeys.readChapterCount)
    }

    static let dependsOn: [any DatabaseRecord.Type] = [
        SeriesRecord.self,
        OriginRecord.self,
        SourceRecord.self,
        MetadataRecord.self,
        CoverRecord.self,
        TitleRecord.self,
        AuthorRecord.self,
        SeriesAuthorRecord.self,
        TagRecord.self,
        SeriesTagRecord.self,
    ]

    static let dependsOnViews: [any ViewRecord.Type] = [
        BestChapterView.self
    ]

    static var viewDefinition: SQLRequest<RichfulEntryView> {
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

                    -- unread count from best chapters (rank = 1 only)
                    COALESCE(
                        (SELECT COUNT(*)
                         FROM \(BestChapterView.databaseTableName) bc
                         WHERE bc.seriesId = m.id
                           AND bc.rank = 1
                           AND bc.progress < 1.0
                           AND (bc.showHalfChapters = 1 OR bc.number = CAST(bc.number AS INTEGER))
                        ), 0
                    ) as unreadCount,

                    (SELECT GROUP_CONCAT(a.name, ', ')
                     FROM \(SeriesAuthorRecord.databaseTableName) ma
                     JOIN \(AuthorRecord.databaseTableName) a ON a.id = ma.authorId
                     WHERE ma.seriesId = m.id
                     ORDER BY a.name
                    ) as authors,

                    -- synopsis: the user's pick of supplier, else the primary origin's
                    COALESCE(
                        (SELECT x.\(MetadataRecord.Columns.synopsis.name)
                         FROM \(MetadataRecord.databaseTableName) x
                         WHERE x.id = m.\(SeriesRecord.Columns.preferredSynopsisId.name)),
                        pm.\(MetadataRecord.Columns.synopsis.name)
                    ) as synopsis,

                    -- canonical only - an alias tag is subsumed under its canonical tag
                    (SELECT GROUP_CONCAT(t.displayName, ', ')
                     FROM \(SeriesTagRecord.databaseTableName) mt
                     JOIN \(TagRecord.databaseTableName) t ON t.id = mt.tagId
                     WHERE mt.seriesId = m.id
                       AND t.canonicalId IS NULL
                     ORDER BY t.displayName
                    ) as tags,

                    -- one pick each - see SeriesRecord.preferredClassificationId/preferredPublicationId
                    COALESCE(
                        (SELECT x.\(MetadataRecord.Columns.classification.name)
                         FROM \(MetadataRecord.databaseTableName) x
                         WHERE x.id = m.\(SeriesRecord.Columns.preferredClassificationId.name)),
                        pm.\(MetadataRecord.Columns.classification.name)
                    ) as classification,

                    COALESCE(
                        (SELECT x.\(MetadataRecord.Columns.publication.name)
                         FROM \(MetadataRecord.databaseTableName) x
                         WHERE x.id = m.\(SeriesRecord.Columns.preferredPublicationId.name)),
                        pm.\(MetadataRecord.Columns.publication.name)
                    ) as publication,

                    m.addedDate,
                    m.updatedDate,
                    m.lastReadDate,
                    m.lastFetchedDate,

                    -- furthest chapter NUMBER read, not most recently opened by date
                    (SELECT MAX(bc.number)
                     FROM \(BestChapterView.databaseTableName) bc
                     WHERE bc.seriesId = m.id
                       AND bc.rank = 1
                       AND bc.progress >= 1.0
                    ) as lastReadChapterNumber,

                    COALESCE(
                        (SELECT COUNT(*)
                         FROM \(BestChapterView.databaseTableName) bc
                         WHERE bc.seriesId = m.id
                           AND bc.rank = 1
                           AND (bc.showHalfChapters = 1 OR bc.number = CAST(bc.number AS INTEGER))
                        ), 0
                    ) as totalChapterCount,

                    COALESCE(
                        (SELECT COUNT(*)
                         FROM \(BestChapterView.databaseTableName) bc
                         WHERE bc.seriesId = m.id
                           AND bc.rank = 1
                           AND bc.progress >= 1.0
                           AND (bc.showHalfChapters = 1 OR bc.number = CAST(bc.number AS INTEGER))
                        ), 0
                    ) as readChapterCount

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

    // no indexes needed - uses indexes from EntryView and BestChapterView
}

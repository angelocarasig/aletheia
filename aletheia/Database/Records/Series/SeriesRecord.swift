//
//  SeriesRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct SeriesRecord: Codable, Hashable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    // user picks. nil falls back to the highest-priority connected origin.
    var preferredTitleId: TitleRecord.ID?
    var preferredCoverId: CoverRecord.ID?
    var preferredSynopsisOriginId: OriginRecord.ID?
    var preferredMetadataOriginId: OriginRecord.ID?

    // config
    var inLibrary: Bool = false
    var status: Status = .planning

    var addedDate: Date = .distantPast
    var updatedDate: Date = .now
    var lastFetchedDate: Date = .now
    var lastReadDate: Date = .distantPast

    var orientation: Orientation = .unknown
    var showAllChapters: Bool = false
    var showHalfChapters: Bool = true

    init() {}
}

// MARK: - DatabaseRecord

extension SeriesRecord {
    static var databaseTableName: String {
        "series"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)

        static let preferredTitleId = Column(CodingKeys.preferredTitleId)
        static let preferredCoverId = Column(CodingKeys.preferredCoverId)
        static let preferredSynopsisOriginId = Column(CodingKeys.preferredSynopsisOriginId)
        static let preferredMetadataOriginId = Column(CodingKeys.preferredMetadataOriginId)

        static let inLibrary = Column(CodingKeys.inLibrary)
        static let status = Column(CodingKeys.status)
        static let addedDate = Column(CodingKeys.addedDate)
        static let updatedDate = Column(CodingKeys.updatedDate)
        static let lastFetchedDate = Column(CodingKeys.lastFetchedDate)
        static let lastReadDate = Column(CodingKeys.lastReadDate)
        static let orientation = Column(CodingKeys.orientation)
        static let showAllChapters = Column(CodingKeys.showAllChapters)
        static let showHalfChapters = Column(CodingKeys.showHalfChapters)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            // forward references - sqlite resolves foreign key targets at dml time,
            // but grdb looks up the target's primary key unless the column is named,
            // so these must be explicit: the tables do not exist yet
            t.column(Columns.preferredTitleId.name, .integer)
                .references(TitleRecord.databaseTableName, column: Columns.id.name, onDelete: .setNull)
            t.column(Columns.preferredCoverId.name, .integer)
                .references(CoverRecord.databaseTableName, column: Columns.id.name, onDelete: .setNull)
            t.column(Columns.preferredSynopsisOriginId.name, .integer)
                .references(OriginRecord.databaseTableName, column: Columns.id.name, onDelete: .setNull)
            t.column(Columns.preferredMetadataOriginId.name, .integer)
                .references(OriginRecord.databaseTableName, column: Columns.id.name, onDelete: .setNull)

            t.column(Columns.inLibrary.name, .boolean).notNull().defaults(to: false)
            t.column(Columns.status.name, .text).notNull().defaults(to: Status.planning.rawValue)
            t.column(Columns.addedDate.name, .datetime).notNull()
            t.column(Columns.updatedDate.name, .datetime).notNull()
            t.column(Columns.lastFetchedDate.name, .datetime).notNull()
            t.column(Columns.lastReadDate.name, .datetime).notNull()

            t.column(Columns.orientation.name, .text).notNull()
            t.column(Columns.showAllChapters.name, .boolean).notNull().defaults(to: false)
            // swift default is true - keep column default aligned
            t.column(Columns.showHalfChapters.name, .boolean).notNull().defaults(to: true)
        }
    }

    static func createIndexes(db: Database) throws {
        // library query filter
        try db.create(index: "idx_series_inLibrary", on: databaseTableName, columns: [Columns.inLibrary.name], ifNotExists: true)

        // sorting with pagination
        try db.create(index: "idx_series_addedDate_id", on: databaseTableName, columns: [
            Columns.addedDate.name,
            Columns.id.name
        ], ifNotExists: true)

        try db.create(index: "idx_series_updatedDate_id", on: databaseTableName, columns: [
            Columns.updatedDate.name,
            Columns.id.name
        ], ifNotExists: true)

        try db.create(index: "idx_series_lastReadDate_id", on: databaseTableName, columns: [
            Columns.lastReadDate.name,
            Columns.id.name
        ], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Series Chapters Association using BestChapterView

extension SeriesRecord {
    /// returns deduplicated chapters based on series preferences using BestChapterView
    var chapters: QueryInterfaceRequest<ChapterRecord> {
        guard let seriesId = self.id else {
            // return empty request if no id
            return ChapterRecord.none()
        }

        // build the SQL that joins with BestChapterView
        let sql = """
            SELECT c.* FROM \(ChapterRecord.databaseTableName) c
            JOIN \(BestChapterView.databaseTableName) bc ON c.id = bc.chapterId
            WHERE bc.seriesId = ?
              AND bc.rank = 1
              AND (? = 1 OR bc.showHalfChapters = 1 OR bc.number = CAST(bc.number AS INTEGER))
            ORDER BY bc.number ASC
            """

        return ChapterRecord.filter(sql: sql, arguments: [seriesId.rawValue, showAllChapters ? 1 : 0])
    }

    /// returns all chapters without deduplication (for showAllChapters mode)
    var allChapters: QueryInterfaceRequest<ChapterRecord> {
        guard let seriesId = self.id else {
            return ChapterRecord.none()
        }

        return ChapterRecord
            .joining(required: ChapterRecord.origin)
            .filter(sql: "\(OriginRecord.databaseTableName).seriesId = ?", arguments: [seriesId.rawValue])
            .order(ChapterRecord.Columns.number.asc)
    }
}

// MARK: - Series Authors Association M-M

extension SeriesRecord {
    static let seriesAuthors = hasMany(SeriesAuthorRecord.self)

    static let authors = hasMany(
        AuthorRecord.self,
        through: seriesAuthors,
        using: SeriesAuthorRecord.author
    )

    var authors: QueryInterfaceRequest<AuthorRecord> {
        request(for: SeriesRecord.authors)
            .order(AuthorRecord.Columns.name.ascNullsLast)
    }
}

// MARK: - Series Tags Association M-M

extension SeriesRecord {
    static let seriesTags = hasMany(SeriesTagRecord.self)

    static let tags = hasMany(
        TagRecord.self,
        through: seriesTags,
        using: SeriesTagRecord.tag
    ).filter(TagRecord.Columns.canonicalId == nil)

    var tags: QueryInterfaceRequest<TagRecord> {
        request(for: SeriesRecord.tags)
            .order(TagRecord.Columns.displayName.ascNullsLast)
    }
}

// MARK: - Series Collections Association M-M

extension SeriesRecord {
    static let seriesCollections = hasMany(SeriesCollectionRecord.self)

    static let collections = hasMany(
        CollectionRecord.self,
        through: seriesCollections,
        using: SeriesCollectionRecord.collection
    )

    var collections: QueryInterfaceRequest<CollectionRecord> {
        request(for: SeriesRecord.collections)
            .order(CollectionRecord.Columns.name)
    }
}

// MARK: - Series Covers Association 1-M

extension SeriesRecord {
    static let covers = hasMany(CoverRecord.self)

    static let preferredCover = belongsTo(CoverRecord.self)

    var covers: QueryInterfaceRequest<CoverRecord> {
        request(for: SeriesRecord.covers)
            .order(CoverRecord.Columns.id.ascNullsLast)
    }

    var preferredCover: QueryInterfaceRequest<CoverRecord> {
        request(for: SeriesRecord.preferredCover)
    }
}

// MARK: - Series Titles Association 1-M

extension SeriesRecord {
    static let titles = hasMany(TitleRecord.self)
        .order(TitleRecord.Columns.value)

    static let preferredTitle = belongsTo(TitleRecord.self)

    var titles: QueryInterfaceRequest<TitleRecord> {
        request(for: SeriesRecord.titles)
    }

    var preferredTitle: QueryInterfaceRequest<TitleRecord> {
        request(for: SeriesRecord.preferredTitle)
    }
}

// MARK: - Series Origins Association 1-M

extension SeriesRecord {
    static let origins = hasMany(OriginRecord.self)
        .order(OriginRecord.Columns.priority.ascNullsLast, OriginRecord.Columns.id.ascNullsLast)

    static let preferredSynopsisOrigin = belongsTo(
        OriginRecord.self,
        key: "preferredSynopsisOrigin",
        using: ForeignKey([Columns.preferredSynopsisOriginId.name])
    )

    static let preferredMetadataOrigin = belongsTo(
        OriginRecord.self,
        key: "preferredMetadataOrigin",
        using: ForeignKey([Columns.preferredMetadataOriginId.name])
    )

    var origin: QueryInterfaceRequest<OriginRecord> {
        request(for: SeriesRecord.origins)
            .limit(1)
    }

    var origins: QueryInterfaceRequest<OriginRecord> {
        request(for: SeriesRecord.origins)
    }

    var preferredSynopsisOrigin: QueryInterfaceRequest<OriginRecord> {
        request(for: SeriesRecord.preferredSynopsisOrigin)
    }

    var preferredMetadataOrigin: QueryInterfaceRequest<OriginRecord> {
        request(for: SeriesRecord.preferredMetadataOrigin)
    }
}

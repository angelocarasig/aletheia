//
//  ChapterRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct ChapterRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    private(set) var originId: OriginRecord.ID
    private(set) var scanlatorId: ScanlatorRecord.ID

    var slug: String
    var title: String
    var number: Double
    var publishedDate: Date
    var language: LanguageCode
    var progress: Double
    var lastReadDate: Date?

    var url: URL
    var path: URL?

    var finished: Bool {
        progress >= 1
    }
}

// MARK: - DatabaseRecord

extension ChapterRecord {
    static var databaseTableName: String {
        "chapter"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let originId = Column(CodingKeys.originId)
        static let scanlatorId = Column(CodingKeys.scanlatorId)

        static let slug = Column(CodingKeys.slug)
        static let title = Column(CodingKeys.title)
        static let number = Column(CodingKeys.number)
        static let publishedDate = Column(CodingKeys.publishedDate)
        static let url = Column(CodingKeys.url)
        static let path = Column(CodingKeys.path)
        static let language = Column(CodingKeys.language)
        static let progress = Column(CodingKeys.progress)
        static let lastReadDate = Column(CodingKeys.lastReadDate)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(OriginRecord.databaseTableName, onDelete: .cascade)
            t.belongsTo(ScanlatorRecord.databaseTableName, onDelete: .restrict)

            t.column(Columns.slug.name, .text).notNull()
            t.column(Columns.title.name, .text).notNull()
            t.column(Columns.number.name, .real).notNull()
            t.column(Columns.publishedDate.name, .datetime).notNull()
            t.column(Columns.url.name, .text).notNull()
            t.column(Columns.language.name, .text).notNull()
            t.column(Columns.progress.name, .real).notNull()
            t.column(Columns.lastReadDate.name, .datetime)
            t.column(Columns.path.name, .text)
        }
    }

    static func createIndexes(db: Database) throws {
        // foreign key indexes
        try db.create(index: "idx_chapter_originId", on: databaseTableName, columns: [Columns.originId.name], ifNotExists: true)
        try db.create(index: "idx_chapter_scanlatorId", on: databaseTableName, columns: [Columns.scanlatorId.name], ifNotExists: true)
        try db.create(index: "idx_chapter_slug", on: databaseTableName, columns: [Columns.slug.name], ifNotExists: true)

        // composite index for deduplication queries
        try db.create(index: "idx_chapter_dedup", on: databaseTableName, columns: [
            Columns.originId.name,
            Columns.number.name
        ], ifNotExists: true)

        // chapter identity within an origin - makes refresh an upsert rather than
        // an append. note: ifNotExists not supported with unique option
        if try !db.indexes(on: databaseTableName).contains(where: { $0.name == "idx_chapter_originId_slug_unique" }) {
            try db.create(
                index: "idx_chapter_originId_slug_unique",
                on: databaseTableName,
                columns: [Columns.originId.name, Columns.slug.name],
                options: .unique
            )
        }

        // progress filtering for read/unread chapters
        try db.create(index: "idx_chapter_progress", on: databaseTableName, columns: [Columns.progress.name], ifNotExists: true)

        // last read chapter lookup and sorting
        try db.create(index: "idx_chapter_lastReadDate", on: databaseTableName, columns: [Columns.lastReadDate.name], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension ChapterRecord {
    static let origin = belongsTo(OriginRecord.self)

    var origin: QueryInterfaceRequest<OriginRecord> {
        request(for: ChapterRecord.origin)
    }
}

extension ChapterRecord {
    static let scanlator = belongsTo(ScanlatorRecord.self)

    var scanlator: QueryInterfaceRequest<ScanlatorRecord> {
        request(for: ChapterRecord.scanlator)
    }
}

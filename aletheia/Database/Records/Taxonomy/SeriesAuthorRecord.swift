//
//  SeriesAuthorRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import GRDB
import Tagged

struct SeriesAuthorRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    var seriesId: SeriesRecord.ID
    var authorId: AuthorRecord.ID
}

// MARK: - DatabaseRecord

extension SeriesAuthorRecord {
    static var databaseTableName: String {
        "series_author"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let authorId = Column(CodingKeys.authorId)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)
            t.belongsTo(AuthorRecord.databaseTableName, onDelete: .cascade)

            t.uniqueKey([Columns.seriesId.name, Columns.authorId.name])
        }
    }

    static func createIndexes(db: Database) throws {
        // same shape as series_tag: the unique key covers seriesId, this covers
        // every series by an author and the cascade when an author goes
        try db.create(index: "idx_series_author_authorId", on: databaseTableName, columns: [Columns.authorId.name], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension SeriesAuthorRecord {
    static let series = belongsTo(SeriesRecord.self)
    static let author = belongsTo(AuthorRecord.self)
}

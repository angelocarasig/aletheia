//
//  SeriesTagRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import GRDB
import Tagged

struct SeriesTagRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    var seriesId: SeriesRecord.ID
    var tagId: TagRecord.ID
}

// MARK: - DatabaseRecord

extension SeriesTagRecord {
    static var databaseTableName: String {
        "series_tag"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let tagId = Column(CodingKeys.tagId)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)
            t.belongsTo(TagRecord.databaseTableName, onDelete: .cascade)

            t.uniqueKey([Columns.seriesId.name, Columns.tagId.name])
        }
    }

    static func createIndexes(db: Database) throws {
        // the unique key is (seriesId, tagId), so only the reverse direction
        // needs one: every series carrying a tag, and the cascade when a tag goes
        try db.create(
            index: "idx_series_tag_tagId", on: databaseTableName, columns: [Columns.tagId.name],
            ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension SeriesTagRecord {
    static let series = belongsTo(SeriesRecord.self)
    static let tag = belongsTo(TagRecord.self)
}

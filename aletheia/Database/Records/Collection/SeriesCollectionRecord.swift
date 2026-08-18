//
//  SeriesCollectionRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct SeriesCollectionRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    var seriesId: SeriesRecord.ID
    var collectionId: CollectionRecord.ID
    var order: Int = 0
    var addedDate: Date = .now
}

// MARK: - DatabaseRecord

extension SeriesCollectionRecord {
    static var databaseTableName: String {
        "series_collection"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let collectionId = Column(CodingKeys.collectionId)
        static let order = Column(CodingKeys.order)
        static let addedDate = Column(CodingKeys.addedDate)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)
            t.belongsTo(CollectionRecord.databaseTableName, onDelete: .cascade)

            t.column(Columns.order.name, .integer).notNull()
            t.column(Columns.addedDate.name, .datetime).notNull()

            t.uniqueKey([Columns.seriesId.name, Columns.collectionId.name])
        }
    }

    static func createIndexes(db: Database) throws {
        // reading a collection's members, and the cascade when one is deleted.
        // ordered, because the order column is what the collection is arranged by
        try db.create(
            index: "idx_series_collection_collectionId", on: databaseTableName,
            columns: [
                Columns.collectionId.name,
                Columns.order.name,
            ], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension SeriesCollectionRecord {
    static let series = belongsTo(SeriesRecord.self)
    static let collection = belongsTo(CollectionRecord.self)
}

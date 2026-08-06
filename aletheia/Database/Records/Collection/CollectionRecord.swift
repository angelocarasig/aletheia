//
//  CollectionRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct CollectionRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    var name: String
    var description: String?
    var createdDate: Date = .now
    var updatedDate: Date = .now
}

// MARK: - DatabaseRecord

extension CollectionRecord {
    static var databaseTableName: String {
        "collection"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let description = Column(CodingKeys.description)
        static let createdDate = Column(CodingKeys.createdDate)
        static let updatedDate = Column(CodingKeys.updatedDate)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.column(Columns.name.name, .text)
                .notNull()
                .collate(.localizedCaseInsensitiveCompare)

            t.column(Columns.description.name, .text)
            t.column(Columns.createdDate.name, .datetime).notNull()
            t.column(Columns.updatedDate.name, .datetime).notNull()
        }
    }

    static func createIndexes(db: Database) throws {
        // sorting collections by name for display
        try db.create(index: "idx_collection_name", on: databaseTableName, columns: [Columns.name.name], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension CollectionRecord {
    static let seriesCollections = hasMany(SeriesCollectionRecord.self)

    static let series = hasMany(
        SeriesRecord.self,
        through: seriesCollections,
        using: SeriesCollectionRecord.series
    ).order(SeriesCollectionRecord.Columns.order)

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: CollectionRecord.series)
    }
}

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

    // "All" is the unfiltered chip and "Library" is what the title falls back to,
    // so either one as a collection makes the current selection unreadable.
    // lowercase, matched case-insensitively
    static let reservedNames: Set<String> = ["all", "library"]

    static func isReserved(_ name: String) -> Bool {
        reservedNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func createTable(db: Database) throws {
        // built from reservedNames so the constraint and the swift check cannot
        // drift apart - enforced at the db level since a future import or sync
        // path could write rows the form never sees
        let reserved = reservedNames.sorted().map { "'\($0)'" }.joined(separator: ", ")

        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.column(Columns.name.name, .text)
                .notNull()
                .collate(.localizedCaseInsensitiveCompare)

            t.column(Columns.description.name, .text)
            t.column(Columns.createdDate.name, .datetime).notNull()
            t.column(Columns.updatedDate.name, .datetime).notNull()

            t.check(sql: "TRIM(LOWER(\(Columns.name.name))) NOT IN (\(reserved))")
        }
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_collection_name", on: databaseTableName, columns: [Columns.name.name],
            ifNotExists: true)
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

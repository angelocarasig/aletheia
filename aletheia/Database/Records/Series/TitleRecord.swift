//
//  TitleRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import GRDB
import Tagged

struct TitleRecord: Codable, DatabaseRecord, UniqueRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    private(set) var seriesId: SeriesRecord.ID
    // provenance, not ownership - null means the supplier's metadata row was
    // deleted, and the title stays in the pool unlabelled rather than being removed
    private(set) var metadataId: MetadataRecord.ID?

    var value: String
}

// MARK: - DatabaseRecord

extension TitleRecord {
    static var databaseTableName: String {
        "title"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let metadataId = Column(CodingKeys.metadataId)
        static let value = Column(CodingKeys.value)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)
            t.column(Columns.metadataId.name, .integer)
                .references(MetadataRecord.databaseTableName, onDelete: .setNull)

            t.column(Columns.value.name, .text)
                .notNull()
                .collate(.localizedCaseInsensitiveCompare)

            t.uniqueKey([Columns.seriesId.name, Columns.value.name])
        }
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_title_seriesId", on: databaseTableName, columns: [Columns.seriesId.name],
            ifNotExists: true)
        try db.create(
            index: "idx_title_metadataId", on: databaseTableName,
            columns: [Columns.metadataId.name], ifNotExists: true)

        // stub matching resolves a title to its series
        try db.create(
            index: "idx_title_value_seriesId", on: databaseTableName,
            columns: [
                Columns.value.name,
                Columns.seriesId.name,
            ], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension TitleRecord {
    static let series = belongsTo(SeriesRecord.self)

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: TitleRecord.series)
    }
}

extension TitleRecord {
    static let metadata = belongsTo(MetadataRecord.self)

    var metadata: QueryInterfaceRequest<MetadataRecord> {
        request(for: TitleRecord.metadata)
    }
}

// MARK: - UniqueRecord

extension TitleRecord {
    static func uniqueFilter(for instance: Self) -> QueryInterfaceRequest<Self> {
        TitleRecord
            .filter(Columns.seriesId == instance.seriesId)
            .filter(Columns.value == instance.value)
    }
}

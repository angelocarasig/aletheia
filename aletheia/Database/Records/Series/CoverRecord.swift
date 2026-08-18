//
//  CoverRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct CoverRecord: Codable, DatabaseRecord, UniqueRecord, StorableRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    private(set) var seriesId: SeriesRecord.ID
    // provenance, not ownership - null means the supplier's metadata row was
    // deleted, and the cover stays in the pool unlabelled rather than being removed
    private(set) var metadataId: MetadataRecord.ID?

    var url: URL
    var path: String?
}

// MARK: - StorableRecord

extension CoverRecord {
    static var storage: URL { Constants.Paths.covers }
    static var pathColumn: Column { Columns.path }
}

// MARK: - DatabaseRecord

extension CoverRecord {
    static var databaseTableName: String {
        "cover"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let metadataId = Column(CodingKeys.metadataId)

        static let url = Column(CodingKeys.url)
        static let path = Column(CodingKeys.path)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)
            t.column(Columns.metadataId.name, .integer)
                .references(MetadataRecord.databaseTableName, onDelete: .setNull)

            t.column(Columns.url.name, .text).notNull()
            t.column(Columns.path.name, .text)

            t.uniqueKey([Columns.seriesId.name, Columns.url.name])
        }
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_cover_seriesId", on: databaseTableName, columns: [Columns.seriesId.name],
            ifNotExists: true)
        try db.create(
            index: "idx_cover_metadataId", on: databaseTableName,
            columns: [Columns.metadataId.name], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension CoverRecord {
    static let series = belongsTo(SeriesRecord.self)

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: CoverRecord.series)
    }
}

extension CoverRecord {
    static let metadata = belongsTo(MetadataRecord.self)

    var metadata: QueryInterfaceRequest<MetadataRecord> {
        request(for: CoverRecord.metadata)
    }
}

// MARK: - UniqueRecord

extension CoverRecord {
    static func uniqueFilter(for instance: Self) -> QueryInterfaceRequest<Self> {
        CoverRecord
            .filter(Columns.seriesId == instance.seriesId)
            .filter(Columns.url == instance.url)
    }
}

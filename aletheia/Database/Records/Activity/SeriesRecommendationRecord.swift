//
//  SeriesRecommendationRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 20/8/2026
//

import Foundation
import GRDB
import Tagged

// one row per (series, pack) - the single source of truth for "what should this
// series show right now." resolution and the computed rail are written together,
// always, so nothing outside this table ever branches on whether a series
// resolved before deciding where to look. catalogId is nil when resolution
// didn't land - a normal, common shape, not an error state
struct SeriesRecommendationRecord: Codable, Hashable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    private(set) var seriesId: SeriesRecord.ID
    private(set) var packId: String

    var catalogId: Int64?

    // fingerprint of the local inputs (titles, tags, and anything else a given
    // recommender scores on) that produced this row - a mismatch means stale,
    // not corrupt. see Payload.fingerprint
    var fingerprint: String

    // json-encoded rail. read/written as one unit, never queried row by row, so
    // a blob beats a child table here
    var rail: Data

    var computedDate: Date = .now

    init(
        seriesId: SeriesRecord.ID,
        packId: String,
        catalogId: Int64?,
        fingerprint: String,
        rail: Data
    ) {
        self.id = nil
        self.seriesId = seriesId
        self.packId = packId
        self.catalogId = catalogId
        self.fingerprint = fingerprint
        self.rail = rail
    }
}

// MARK: - DatabaseRecord

extension SeriesRecommendationRecord {
    static var databaseTableName: String {
        "series_recommendation"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let packId = Column(CodingKeys.packId)
        static let catalogId = Column(CodingKeys.catalogId)
        static let fingerprint = Column(CodingKeys.fingerprint)
        static let rail = Column(CodingKeys.rail)
        static let computedDate = Column(CodingKeys.computedDate)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)

            t.column(Columns.packId.name, .text).notNull()
            t.column(Columns.catalogId.name, .integer)
            t.column(Columns.fingerprint.name, .text).notNull()
            t.column(Columns.rail.name, .blob).notNull()
            t.column(Columns.computedDate.name, .datetime).notNull()

            t.uniqueKey([Columns.seriesId.name, Columns.packId.name])
        }
    }

    static func createIndexes(db: Database) throws {
        // the unique key above already covers reads keyed by series, so this is
        // for the cascade - same shape as idx_series_tracker_seriesId
        try db.create(
            index: "idx_series_recommendation_seriesId",
            on: databaseTableName,
            columns: [Columns.seriesId.name],
            ifNotExists: true
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension SeriesRecommendationRecord {
    static let series = belongsTo(SeriesRecord.self)

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: SeriesRecommendationRecord.series)
    }
}

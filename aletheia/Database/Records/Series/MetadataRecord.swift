//
//  MetadataRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation
import GRDB
import Tagged

// what one supplier says a series is. an origin owns one of these and so does a
// tracker link, which is the whole point: publication and classification had no
// home outside origin, and admitting a chapterless row into origin forks the
// meaning of sourceId IS NULL at eighteen sites.
// see docs/features/tracker-metadata.md §6.1
struct MetadataRecord: Codable, DatabaseRecord, UniqueRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    private(set) var seriesId: SeriesRecord.ID

    // the live link. at most one is set, and both go null when the supplier is
    // removed - a metadata row outlives its supplier exactly as cover and title
    // rows already do, so removing a source does not take its synopsis or
    // silently clear a pin pointing at it
    var originId: OriginRecord.ID?
    var trackerId: SeriesTrackerRecord.ID?

    // the durable identity the foreign keys are not. written once, never nulled,
    // so a removed supplier's row can still be labelled, and re-adopted rather
    // than duplicated when that supplier comes back
    private(set) var supplier: String

    var synopsis: String
    var classification: Classification
    var publication: Publication
    var fetchedDate: Date = .distantPast

    // no supplier left. the row is still pinnable and still labelled through
    // supplier, but it can never win automatic resolution, because resolution
    // runs through origin priority and this has no origin
    var detached: Bool {
        originId == nil && trackerId == nil
    }

    init(
        seriesId: SeriesRecord.ID,
        originId: OriginRecord.ID? = nil,
        trackerId: SeriesTrackerRecord.ID? = nil,
        supplier: String,
        synopsis: String,
        classification: Classification,
        publication: Publication,
        fetchedDate: Date = .distantPast
    ) {
        self.id = nil
        self.seriesId = seriesId
        self.originId = originId
        self.trackerId = trackerId
        self.supplier = supplier
        self.synopsis = synopsis
        self.classification = classification
        self.publication = publication
        self.fetchedDate = fetchedDate
    }
}

// MARK: - Supplier identity

extension MetadataRecord {
    // the origin slug is not decoration. origin is unique on (sourceId, slug)
    // globally, so two origins of one series from one source are guaranteed to
    // differ by slug - without it they collide on (seriesId, supplier) and the
    // second one's metadata is silently never stored
    static func supplier(source: String, origin: String) -> String {
        "source:\(source):\(origin)"
    }

    // no third segment: series_tracker is already unique on (seriesId, tracker)
    static func supplier(tracker: Tracker) -> String {
        "tracker:\(tracker.rawValue)"
    }
}

// MARK: - DatabaseRecord

extension MetadataRecord {
    static var databaseTableName: String {
        "metadata"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let originId = Column(CodingKeys.originId)
        static let trackerId = Column(CodingKeys.trackerId)
        static let supplier = Column(CodingKeys.supplier)

        static let synopsis = Column(CodingKeys.synopsis)
        static let classification = Column(CodingKeys.classification)
        static let publication = Column(CodingKeys.publication)
        static let fetchedDate = Column(CodingKeys.fetchedDate)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)

            // set null, never cascade. cascading would delete the synopsis and
            // clear the pin the moment a source is removed, which is the bug
            // this table exists to close
            t.column(Columns.originId.name, .integer)
                .references(OriginRecord.databaseTableName, onDelete: .setNull)
            t.column(Columns.trackerId.name, .integer)
                .references(SeriesTrackerRecord.databaseTableName, onDelete: .setNull)

            t.column(Columns.supplier.name, .text).notNull()

            t.column(Columns.synopsis.name, .text).notNull()
            t.column(Columns.classification.name, .text).notNull()
            t.column(Columns.publication.name, .text).notNull()
            t.column(Columns.fetchedDate.name, .datetime).notNull()

            // at most one, not exactly one. exactly-one would force cascade on
            // both supplier keys, since set null would violate it
            t.check(sql: "\(Columns.originId.name) IS NULL OR \(Columns.trackerId.name) IS NULL")

            // one row per supplier per series, which is what makes a removed
            // source re-adopt its row instead of minting a second one
            t.uniqueKey([Columns.seriesId.name, Columns.supplier.name])
        }
    }

    static func createIndexes(db: Database) throws {
        // the unique key above is (seriesId, supplier), so reads and the cascade
        // keyed by series already ride its leftmost column. these two are for
        // the set null on supplier delete and for re-adoption on re-attach
        try db.create(
            index: "idx_metadata_originId",
            on: databaseTableName,
            columns: [Columns.originId.name],
            ifNotExists: true
        )

        try db.create(
            index: "idx_metadata_trackerId",
            on: databaseTableName,
            columns: [Columns.trackerId.name],
            ifNotExists: true
        )

        // library filtering, moved here from origin with the columns
        try db.create(
            index: "idx_metadata_seriesId_publication",
            on: databaseTableName,
            columns: [Columns.seriesId.name, Columns.publication.name],
            ifNotExists: true
        )

        try db.create(
            index: "idx_metadata_seriesId_classification",
            on: databaseTableName,
            columns: [Columns.seriesId.name, Columns.classification.name],
            ifNotExists: true
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - UniqueRecord

extension MetadataRecord {
    static func uniqueFilter(for instance: Self) -> QueryInterfaceRequest<Self> {
        filter(Columns.seriesId == instance.seriesId && Columns.supplier == instance.supplier)
    }

    // find-or-create on the durable identity, then re-point the live key. the
    // second half is the part findOrCreate cannot do on its own: it returns an
    // existing row untouched, so a source removed and added back would keep
    // rendering as removed forever while its pin still worked
    static func adopt(
        seriesId: SeriesRecord.ID,
        supplier: String,
        originId: OriginRecord.ID? = nil,
        trackerId: SeriesTrackerRecord.ID? = nil,
        in db: Database
    ) throws -> MetadataRecord {
        var row = try findOrCreate(
            MetadataRecord(
                seriesId: seriesId,
                originId: originId,
                trackerId: trackerId,
                supplier: supplier,
                synopsis: "",
                classification: .Unknown,
                publication: .Unknown
            ),
            in: db
        )

        if row.originId != originId || row.trackerId != trackerId {
            _ = try row.updateChanges(db) {
                $0.originId = originId
                $0.trackerId = trackerId
            }
        }

        return row
    }
}

// MARK: - Associations

extension MetadataRecord {
    static let series = belongsTo(SeriesRecord.self)
    static let origin = belongsTo(OriginRecord.self)
    static let tracker = belongsTo(SeriesTrackerRecord.self)
}

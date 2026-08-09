//
//  ReadingEventRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged

struct ReadingEventRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    // no foreign key on purpose - history must survive the launch purge and
    // series merges, so joins are best-effort and the snapshot names the row
    // when they fail; see docs/features/activity-history.md §1
    var kind: Kind
    var seriesId: SeriesRecord.ID
    var seriesTitle: String
    var chapterNumber: Double
    var occurredDate: Date
    var localDayKey: Int

    init(kind: Kind, seriesId: SeriesRecord.ID, seriesTitle: String, chapterNumber: Double, occurredDate: Date = .now) {
        self.kind = kind
        self.seriesId = seriesId
        self.seriesTitle = seriesTitle
        self.chapterNumber = chapterNumber
        self.occurredDate = occurredDate
        self.localDayKey = occurredDate.localDayKey
    }
}

// MARK: - Kind

extension ReadingEventRecord {
    enum Kind: String, Codable {
        case chapterCompleted
    }
}

// MARK: - DatabaseRecord

extension ReadingEventRecord {
    static var databaseTableName: String {
        "reading_event"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let kind = Column(CodingKeys.kind)
        static let seriesId = Column(CodingKeys.seriesId)
        static let seriesTitle = Column(CodingKeys.seriesTitle)
        static let chapterNumber = Column(CodingKeys.chapterNumber)
        static let occurredDate = Column(CodingKeys.occurredDate)
        static let localDayKey = Column(CodingKeys.localDayKey)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)
            t.column(Columns.kind.name, .text).notNull()
            t.column(Columns.seriesId.name, .integer).notNull()
            t.column(Columns.seriesTitle.name, .text).notNull()
            t.column(Columns.chapterNumber.name, .double).notNull()
            t.column(Columns.occurredDate.name, .datetime).notNull()
            t.column(Columns.localDayKey.name, .integer).notNull()
        }
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_reading_event_localDayKey",
            on: databaseTableName,
            columns: [Columns.localDayKey.name],
            ifNotExists: true
        )
        try db.create(
            index: "idx_reading_event_seriesId_occurredDate",
            on: databaseTableName,
            columns: [Columns.seriesId.name, Columns.occurredDate.name],
            ifNotExists: true
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

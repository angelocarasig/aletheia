//
//  ReadingSessionRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged

struct ReadingSessionRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    // no foreign key on purpose - same survival rationale as ReadingEventRecord.
    // rows are inserted complete, never opened and later closed - endedDate is
    // non-null by construction so a stranded open session is unrepresentable;
    // see docs/features/activity-history.md §7.1
    var seriesId: SeriesRecord.ID
    var seriesTitle: String
    var pagesRead: Int
    var chaptersRead: Int
    var startedDate: Date
    var endedDate: Date
    var localDayKey: Int

    init(
        seriesId: SeriesRecord.ID, seriesTitle: String, pagesRead: Int, chaptersRead: Int,
        startedDate: Date, endedDate: Date
    ) {
        self.seriesId = seriesId
        self.seriesTitle = seriesTitle
        self.pagesRead = pagesRead
        self.chaptersRead = chaptersRead
        self.startedDate = startedDate
        self.endedDate = endedDate
        self.localDayKey = endedDate.localDayKey
    }
}

// MARK: - DatabaseRecord

extension ReadingSessionRecord {
    static var databaseTableName: String {
        "reading_session"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let seriesTitle = Column(CodingKeys.seriesTitle)
        static let pagesRead = Column(CodingKeys.pagesRead)
        static let chaptersRead = Column(CodingKeys.chaptersRead)
        static let startedDate = Column(CodingKeys.startedDate)
        static let endedDate = Column(CodingKeys.endedDate)
        static let localDayKey = Column(CodingKeys.localDayKey)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)
            t.column(Columns.seriesId.name, .integer).notNull()
            t.column(Columns.seriesTitle.name, .text).notNull()
            t.column(Columns.pagesRead.name, .integer).notNull()
            t.column(Columns.chaptersRead.name, .integer).notNull()
            t.column(Columns.startedDate.name, .datetime).notNull()
            t.column(Columns.endedDate.name, .datetime).notNull()
            t.column(Columns.localDayKey.name, .integer).notNull()
        }
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_reading_session_localDayKey",
            on: databaseTableName,
            columns: [Columns.localDayKey.name],
            ifNotExists: true
        )

        try db.create(
            index: "idx_reading_session_seriesId_startedDate",
            on: databaseTableName,
            columns: [Columns.seriesId.name, Columns.startedDate.name],
            ifNotExists: true
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

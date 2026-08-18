//
//  SeriesLanguagePriorityRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation
import GRDB
import Tagged

// which language wins when the same chapter exists in several. ranked above
// origin in best_chapter on purpose: a source you trust is a preference, a
// language you cannot read is a wall, and the preferred source's chinese copy is
// worth nothing next to a lower source's english one.
//
// scoped to the series rather than the origin because it is consulted before
// origin - the rows it compares come from different sources
struct SeriesLanguagePriorityRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    private(set) var seriesId: SeriesRecord.ID
    // a column, not a foreign key - LanguageCode is an enum stored as text, and
    // there is no language table for it to point at
    var language: LanguageCode
    var priority: Int

    init(seriesId: SeriesRecord.ID, language: LanguageCode, priority: Int) {
        self.id = nil
        self.seriesId = seriesId
        self.language = language
        self.priority = priority
    }
}

// MARK: - DatabaseRecord

extension SeriesLanguagePriorityRecord {
    static var databaseTableName: String {
        "series_language_priority"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)

        static let language = Column(CodingKeys.language)
        static let priority = Column(CodingKeys.priority)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)

            t.column(Columns.language.name, .text).notNull()
            t.column(Columns.priority.name, .integer).notNull()

            t.uniqueKey([Columns.seriesId.name, Columns.language.name])
        }
    }

    static func createIndexes(db: Database) throws {
        // foreign key index
        try db.create(
            index: "idx_series_language_priority_seriesId",
            on: databaseTableName,
            columns: [Columns.seriesId.name],
            ifNotExists: true
        )

        // covers the join best_chapter makes on every ranked chapter
        try db.create(
            index: "idx_series_language_priority_covering",
            on: databaseTableName,
            columns: [
                Columns.seriesId.name,
                Columns.language.name,
                Columns.priority.name,
            ],
            ifNotExists: true
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Seeding

extension SeriesLanguagePriorityRecord {
    // every series carries all four rows in the default order from creation -
    // ranking never depends on a row being absent. insert-or-ignore, so calling
    // this again (chapter refresh healing a series that predates seeding) never
    // touches an order the reader has since set
    static func seedDefaults(for seriesId: SeriesRecord.ID, in db: Database) throws {
        for (index, language) in LanguageCode.defaultPriority.enumerated() {
            var row = SeriesLanguagePriorityRecord(
                seriesId: seriesId,
                language: language,
                priority: index
            )
            try row.insert(db, onConflict: .ignore)
        }
    }
}

// MARK: - Associations

extension SeriesLanguagePriorityRecord {
    static let series = belongsTo(SeriesRecord.self)

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: SeriesLanguagePriorityRecord.series)
    }
}

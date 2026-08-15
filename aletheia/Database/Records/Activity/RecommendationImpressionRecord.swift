//
//  RecommendationImpressionRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Foundation
import GRDB
import Tagged

// what the reader was actually shown, which nothing else in this database
// records. a recommendation can only be acted on if it reached the screen, so
// without this "shown and ignored" and "never shown" are the same absence - and
// they are opposite diagnoses, one about the recommendation and one about where
// it was placed
//
// the rest of the funnel is NOT here on purpose. added to library, chapters
// read, completed, dropped and re-read are already answerable from series,
// chapter and reading_event, and logging them twice would create a second
// account of the same fact that can disagree with the first
struct RecommendationImpressionRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    // no foreign key, on two counts. catalogId names a row in the frozen model
    // bundle, which has no table here at all; and seedSeriesId follows
    // reading_event, whose comment applies unchanged - history must outlive the
    // launch purge and series merges
    var catalogId: Int64
    var catalogTitle: String
    var seedSeriesId: SeriesRecord.ID
    // null on the projected path, where the seed resolved to no catalogue row
    var seedCatalogId: Int64?

    // one render of the rail. without it, three rows are three unrelated events
    // rather than a set the reader chose between, and the choice is the signal
    var batchId: String
    var rank: Int
    var surface: String
    var modelVersion: String

    // what the model claimed at the time. the model will change, and a judgement
    // re-scored with later weights is not evidence about the decision that was
    // actually made - the two metrics that already failed here failed by being
    // applied after the fact
    var score: Double
    var confidence: Double
    var blockTag: Double
    var blockEmbedding: Double
    var blockEra: Double

    // membership moves, so this has to be the answer at show time. ignoring a
    // recommendation for something already owned means something different from
    // ignoring a new one, and a join would report today's answer instead
    var alreadyInLibrary: Bool
    // reserved for the position experiment: two otherwise equal recommendations
    // swapped, to separate rank from quality. nothing writes true yet
    var shuffled: Bool

    // null means shown and not acted on, which is the whole point of the table
    var tappedDate: Date?
    var occurredDate: Date
    var localDayKey: Int

    init(catalogId: Int64,
         catalogTitle: String,
         seedSeriesId: SeriesRecord.ID,
         seedCatalogId: Int64?,
         batchId: String,
         rank: Int,
         surface: Surface = .detailsRail,
         modelVersion: String,
         score: Double,
         confidence: Double,
         blockTag: Double,
         blockEmbedding: Double,
         blockEra: Double,
         alreadyInLibrary: Bool,
         shuffled: Bool = false,
         occurredDate: Date = .now) {
        self.catalogId = catalogId
        self.catalogTitle = catalogTitle
        self.seedSeriesId = seedSeriesId
        self.seedCatalogId = seedCatalogId
        self.batchId = batchId
        self.rank = rank
        self.surface = surface.rawValue
        self.modelVersion = modelVersion
        self.score = score
        self.confidence = confidence
        self.blockTag = blockTag
        self.blockEmbedding = blockEmbedding
        self.blockEra = blockEra
        self.alreadyInLibrary = alreadyInLibrary
        self.shuffled = shuffled
        self.occurredDate = occurredDate
        self.localDayKey = occurredDate.localDayKey
    }
}

// MARK: - Surface

extension RecommendationImpressionRecord {
    // stored as text rather than an int: a surface added later must not depend on
    // the order this enum happens to be written in
    enum Surface: String, Codable {
        case detailsRail
    }
}

// MARK: - DatabaseRecord

extension RecommendationImpressionRecord {
    static var databaseTableName: String {
        "recommendation_impression"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let catalogId = Column(CodingKeys.catalogId)
        static let catalogTitle = Column(CodingKeys.catalogTitle)
        static let seedSeriesId = Column(CodingKeys.seedSeriesId)
        static let seedCatalogId = Column(CodingKeys.seedCatalogId)
        static let batchId = Column(CodingKeys.batchId)
        static let rank = Column(CodingKeys.rank)
        static let surface = Column(CodingKeys.surface)
        static let modelVersion = Column(CodingKeys.modelVersion)
        static let score = Column(CodingKeys.score)
        static let confidence = Column(CodingKeys.confidence)
        static let blockTag = Column(CodingKeys.blockTag)
        static let blockEmbedding = Column(CodingKeys.blockEmbedding)
        static let blockEra = Column(CodingKeys.blockEra)
        static let alreadyInLibrary = Column(CodingKeys.alreadyInLibrary)
        static let shuffled = Column(CodingKeys.shuffled)
        static let tappedDate = Column(CodingKeys.tappedDate)
        static let occurredDate = Column(CodingKeys.occurredDate)
        static let localDayKey = Column(CodingKeys.localDayKey)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)
            t.column(Columns.catalogId.name, .integer).notNull()
            t.column(Columns.catalogTitle.name, .text).notNull()
            t.column(Columns.seedSeriesId.name, .integer).notNull()
            t.column(Columns.seedCatalogId.name, .integer)
            t.column(Columns.batchId.name, .text).notNull()
            t.column(Columns.rank.name, .integer).notNull()
            t.column(Columns.surface.name, .text).notNull()
            t.column(Columns.modelVersion.name, .text).notNull()
            t.column(Columns.score.name, .double).notNull()
            t.column(Columns.confidence.name, .double).notNull()
            t.column(Columns.blockTag.name, .double).notNull()
            t.column(Columns.blockEmbedding.name, .double).notNull()
            t.column(Columns.blockEra.name, .double).notNull()
            t.column(Columns.alreadyInLibrary.name, .boolean).notNull()
            t.column(Columns.shuffled.name, .boolean).notNull()
            t.column(Columns.tappedDate.name, .datetime)
            t.column(Columns.occurredDate.name, .datetime).notNull()
            t.column(Columns.localDayKey.name, .integer).notNull()
        }
    }

    static func createIndexes(db: Database) throws {
        // the tap is written by id, but every read is by what was shown
        try db.create(
            index: "idx_recommendation_impression_catalogId",
            on: databaseTableName,
            columns: [Columns.catalogId.name],
            ifNotExists: true
        )
        // "what has this series already shown, and was any of it taken"
        try db.create(
            index: "idx_recommendation_impression_seed_occurredDate",
            on: databaseTableName,
            columns: [Columns.seedSeriesId.name, Columns.occurredDate.name],
            ifNotExists: true
        )
        // one render, for the choice-set reads that ask what competed
        try db.create(
            index: "idx_recommendation_impression_batchId",
            on: databaseTableName,
            columns: [Columns.batchId.name],
            ifNotExists: true
        )
        try db.create(
            index: "idx_recommendation_impression_localDayKey",
            on: databaseTableName,
            columns: [Columns.localDayKey.name],
            ifNotExists: true
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

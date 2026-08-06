//
//  OriginRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct OriginRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?
    private(set) var seriesId: SeriesRecord.ID
    private(set) var sourceId: SourceRecord.ID? // mutate only via TableRecord.delete()

    private(set) var slug: String
    private(set) var url: String
    var synopsis: String
    var priority: Int
    var classification: Classification
    var publication: Publication

    // distantPast means never fetched, which is what lets an empty chapter list
    // be told apart from one that has simply not loaded yet. metadata and
    // chapters land seconds and minutes apart, so they are tracked separately
    var metadataFetchedDate: Date = .distantPast
    var chaptersFetchedDate: Date = .distantPast

    var disconnected: Bool {
        sourceId == nil
    }
}

// MARK: - DatabaseRecord

extension OriginRecord {
    static var databaseTableName: String {
        "origin"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let sourceId = Column(CodingKeys.sourceId)

        static let slug = Column(CodingKeys.slug)
        static let url = Column(CodingKeys.url)
        static let synopsis = Column(CodingKeys.synopsis)
        static let priority = Column(CodingKeys.priority)
        static let classification = Column(CodingKeys.classification)
        static let publication = Column(CodingKeys.publication)

        static let metadataFetchedDate = Column(CodingKeys.metadataFetchedDate)
        static let chaptersFetchedDate = Column(CodingKeys.chaptersFetchedDate)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)
            t.column(Columns.sourceId.name, .integer)
                .references(SourceRecord.databaseTableName, onDelete: .setNull)

            t.column(Columns.slug.name, .text).notNull().indexed()
            t.column(Columns.url.name, .text).notNull()
            t.column(Columns.synopsis.name, .text).notNull()
            t.column(Columns.priority.name, .integer).notNull().defaults(to: 0)
            t.column(Columns.classification.name, .text).notNull()
            t.column(Columns.publication.name, .text).notNull()

            t.column(Columns.metadataFetchedDate.name, .datetime).notNull()
            t.column(Columns.chaptersFetchedDate.name, .datetime).notNull()
        }
    }

    static func createIndexes(db: Database) throws {
        // foreign key indexes
        try db.create(index: "idx_origin_seriesId", on: databaseTableName, columns: [Columns.seriesId.name], ifNotExists: true)
        try db.create(index: "idx_origin_sourceId", on: databaseTableName, columns: [Columns.sourceId.name], ifNotExists: true)

        // composite index for origin priority lookup
        try db.create(index: "idx_origin_priority", on: databaseTableName, columns: [
            Columns.seriesId.name,
            Columns.priority.name
        ], ifNotExists: true)

        // a source's slug resolves to at most one origin. sourceId is nullable and
        // sqlite treats nulls as distinct, so disconnected origins never collide.
        // note: ifNotExists not supported with unique option - guard manually
        if try !db.indexes(on: databaseTableName).contains(where: { $0.name == "idx_origin_sourceId_slug_unique" }) {
            try db.create(
                index: "idx_origin_sourceId_slug_unique",
                on: databaseTableName,
                columns: [Columns.sourceId.name, Columns.slug.name],
                options: .unique
            )
        }

        // library filtering by publication/classification
        try db.create(index: "idx_origin_seriesId_publication", on: databaseTableName, columns: [
            Columns.seriesId.name,
            Columns.publication.name
        ], ifNotExists: true)

        try db.create(index: "idx_origin_seriesId_classification", on: databaseTableName, columns: [
            Columns.seriesId.name,
            Columns.classification.name
        ], ifNotExists: true)

        // covering index for origin lookups by series and source
        try db.create(index: "idx_origin_seriesId_sourceId", on: databaseTableName, columns: [
            Columns.seriesId.name,
            Columns.sourceId.name
        ], ifNotExists: true)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension OriginRecord {
    static let series = belongsTo(SeriesRecord.self)

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: OriginRecord.series)
    }
}

extension OriginRecord {
    static let source = belongsTo(SourceRecord.self)

    var source: QueryInterfaceRequest<SourceRecord> {
        request(for: OriginRecord.source)
    }
}

extension OriginRecord {
    static let chapters = hasMany(ChapterRecord.self)

    var chapters: QueryInterfaceRequest<ChapterRecord> {
        request(for: OriginRecord.chapters)
    }
}

extension OriginRecord {
    static let scanlatorPriorities = hasMany(OriginScanlatorPriorityRecord.self)
        .order(OriginScanlatorPriorityRecord.Columns.priority.asc)

    static let prioritizedScanlators = hasMany(
        ScanlatorRecord.self,
        through: scanlatorPriorities,
        using: OriginScanlatorPriorityRecord.scanlator
    )

    var prioritizedScanlators: QueryInterfaceRequest<ScanlatorRecord> {
        request(for: OriginRecord.prioritizedScanlators)
    }
}

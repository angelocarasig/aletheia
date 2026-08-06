//
//  ScanlatorRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct ScanlatorRecord: Codable, DatabaseRecord, UniqueRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    var name: String
}

// MARK: - DatabaseRecord

extension ScanlatorRecord {
    static var databaseTableName: String {
        "scanlator"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            // unique constraint on name also creates a supporting index
            t.column(Columns.name.name, .text).notNull().unique()
        }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension ScanlatorRecord {
    static let chapters = hasMany(ChapterRecord.self)
        .order(ChapterRecord.Columns.publishedDate.desc)

    var chapters: QueryInterfaceRequest<ChapterRecord> {
        request(for: ScanlatorRecord.chapters)
    }
}

extension ScanlatorRecord {
    static let originPriorities = hasMany(OriginScanlatorPriorityRecord.self)

    static let prioritizedOrigins = hasMany(
        OriginRecord.self,
        through: originPriorities,
        using: OriginScanlatorPriorityRecord.origin
    )
}

// MARK: - UniqueRecord

extension ScanlatorRecord {
    static func uniqueFilter(for instance: Self) -> QueryInterfaceRequest<Self> {
        ScanlatorRecord.filter(Columns.name == instance.name)
    }
}

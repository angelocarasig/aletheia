//
//  AuthorRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct AuthorRecord: Codable, DatabaseRecord, UniqueRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    var name: String
}

// MARK: - DatabaseRecord

extension AuthorRecord {
    static var databaseTableName: String {
        "author"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            t.column(Columns.name.name, .text)
                .notNull()
                .unique()
                .collate(.localizedCaseInsensitiveCompare)
        }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension AuthorRecord {
    static let seriesAuthors = hasMany(SeriesAuthorRecord.self)

    static let series = hasMany(
        SeriesRecord.self,
        through: seriesAuthors,
        using: SeriesAuthorRecord.series
    )

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: AuthorRecord.series)
    }
}

// MARK: - UniqueRecord

extension AuthorRecord {
    static func uniqueFilter(for instance: Self) -> QueryInterfaceRequest<Self> {
        AuthorRecord.filter(Columns.name == instance.name)
    }
}

extension AuthorRecord {
    // every writer joins through here, so none of them records where the author came from
    @discardableResult
    static func attach(_ name: String, to series: SeriesRecord.ID, in db: Database) throws
        -> AuthorRecord.ID?
    {
        let author = try findOrCreate(AuthorRecord(id: nil, name: name), in: db)
        guard let authorId = author.id else { return nil }

        var link = SeriesAuthorRecord(id: nil, seriesId: series, authorId: authorId)
        try link.insert(db, onConflict: .ignore)
        return authorId
    }
}

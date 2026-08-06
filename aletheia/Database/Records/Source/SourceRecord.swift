//
//  SourceRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB
import Tagged

struct SourceRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?
    
    var slug: String
    var hash: String
    var pinned: Bool = false
    var disabled: Bool = false
    
    init(
        slug: String,
        hash: String,
        pinned: Bool = false,
        disabled: Bool = false
    ) {
        self.id = nil
        self.slug = slug
        self.hash = hash
        self.pinned = pinned
        self.disabled = disabled
    }
}

extension SourceRecord {
    init(descriptor: SourceDescriptor) {
        self.init(slug: descriptor.slug, hash: descriptor.fingerprint)
    }
}

// MARK: - DatabaseRecord

extension SourceRecord {
    static var databaseTableName: String {
        "source"
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        
        static let slug = Column(CodingKeys.slug)
        static let hash = Column(CodingKeys.hash)
        static let pinned = Column(CodingKeys.pinned)
        static let disabled = Column(CodingKeys.disabled)
    }
    
    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)
            t.column(Columns.slug.name, .text).notNull().unique()
            t.column(Columns.hash.name, .text).notNull()
            t.column(Columns.pinned.name, .boolean).notNull().defaults(to: false)
            t.column(Columns.disabled.name, .boolean).notNull().defaults(to: false)
        }
    }
    
    static func createIndexes(db: Database) throws {
        // slug lookups (also enforced unique at column level)
        try db.create(index: "idx_source_slug", on: databaseTableName, columns: [Columns.slug.name], ifNotExists: true)
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension SourceRecord {
    static let origins = hasMany(OriginRecord.self)
    
    var origins: QueryInterfaceRequest<OriginRecord> {
        request(for: SourceRecord.origins)
    }
}

extension SourceRecord {
    static func reconcile(with sources: [SourceRecord], in db: Database) throws {
        let incoming = Dictionary(uniqueKeysWithValues: sources.map { ($0.slug, $0) })
        let existing = try SourceRecord.fetchAll(db)
        let existingBySlug = Dictionary(uniqueKeysWithValues: existing.map { ($0.slug, $0) })

        for row in existing where incoming[row.slug] == nil {
            try row.delete(db)
        }

        for source in sources {
            if var current = existingBySlug[source.slug] {
                if current.hash != source.hash {
                    current.hash = source.hash
                    try current.update(db)
                }
            } else {
                var new = source
                try new.insert(db)
            }
        }
    }
}

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
    var name: String
    var hash: String

    // held here rather than only on the descriptor so a series can still show and
    // load its covers after the source stops shipping with the app
    var baseURL: URL
    var referer: URL

    var pinned: Bool = false
    var disabled: Bool = false
    var installed: Bool = true

    init(
        slug: String,
        name: String,
        hash: String,
        baseURL: URL,
        referer: URL,
        pinned: Bool = false,
        disabled: Bool = false,
        installed: Bool = true
    ) {
        self.id = nil
        self.slug = slug
        self.name = name
        self.hash = hash
        self.baseURL = baseURL
        self.referer = referer
        self.pinned = pinned
        self.disabled = disabled
        self.installed = installed
    }
}

extension SourceRecord {
    init(descriptor: SourceDescriptor) {
        self.init(
            slug: descriptor.slug,
            name: descriptor.name,
            hash: descriptor.fingerprint,
            baseURL: descriptor.baseURL,
            referer: descriptor.referer
        )
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
        static let name = Column(CodingKeys.name)
        static let hash = Column(CodingKeys.hash)
        static let baseURL = Column(CodingKeys.baseURL)
        static let referer = Column(CodingKeys.referer)
        static let pinned = Column(CodingKeys.pinned)
        static let disabled = Column(CodingKeys.disabled)
        static let installed = Column(CodingKeys.installed)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)
            t.column(Columns.slug.name, .text).notNull().unique()
            t.column(Columns.name.name, .text).notNull()
            t.column(Columns.hash.name, .text).notNull()
            t.column(Columns.baseURL.name, .text).notNull()
            t.column(Columns.referer.name, .text).notNull()
            t.column(Columns.pinned.name, .boolean).notNull().defaults(to: false)
            t.column(Columns.disabled.name, .boolean).notNull().defaults(to: false)
            t.column(Columns.installed.name, .boolean).notNull().defaults(to: true)
        }
    }

    static func createIndexes(db: Database) throws {
        // slug lookups (also enforced unique at column level)
        try db.create(
            index: "idx_source_slug", on: databaseTableName, columns: [Columns.slug.name],
            ifNotExists: true)
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

        // marked, not deleted. deleting takes the name and referer with it and nulls
        // every origin's sourceId, so a series loses its covers and its link to the
        // source that supplied them. the row stays as a tombstone and reinstalling
        // the source flips it back with its origins intact
        for row in existing where incoming[row.slug] == nil {
            guard row.installed else { continue }
            var uninstalled = row
            uninstalled.installed = false
            try uninstalled.update(db)
        }

        for source in sources {
            if var current = existingBySlug[source.slug] {
                _ = try current.updateChanges(db) {
                    $0.name = source.name
                    $0.hash = source.hash
                    $0.baseURL = source.baseURL
                    $0.referer = source.referer
                    $0.installed = true
                }
            } else {
                var new = source
                try new.insert(db)
            }
        }
    }
}

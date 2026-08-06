//
//  DatabaseRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import GRDB
import Tagged

protocol DatabaseRecord: FetchableRecord, MutablePersistableRecord, TableRecord {
    associatedtype ID = Tagged<Self, Int64>

    /// primary key for the record
    var id: ID? { get }

    /// the database table name for this record
    static var databaseTableName: String { get }

    /// creates the initial table schema (v1.0.0)
    static func createTable(db: Database) throws

    /// creates index optimizations (v1.0.1)
    /// only create indexes here - schema changes belong in createTable
    static func createIndexes(db: Database) throws
}

// MARK: - Default Implementations

extension DatabaseRecord {
    static func createIndexes(db: Database) throws {
        // override in records that need indexes
    }
}

// MARK: - Helper Extensions

extension DatabaseRecord {
    static func exists(in db: Database) throws -> Bool {
        try db.tableExists(databaseTableName)
    }

    static func drop(db: Database) throws {
        if try exists(in: db) {
            try db.drop(table: databaseTableName)
        }
    }
}

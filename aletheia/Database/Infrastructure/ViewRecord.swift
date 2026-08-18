//
//  ViewRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import GRDB

enum ViewError: Error {
    case missingTableDependency(view: String, table: String)
    case missingViewDependency(view: String, dependency: String)
}

protocol ViewRecord: Codable, FetchableRecord, TableRecord {
    /// the database view name
    static var databaseTableName: String { get }

    /// the SQL request that defines the view
    static var viewDefinition: SQLRequest<Self> { get }

    /// tables this view depends on - used to determine when to rebuild
    static var dependsOn: [any DatabaseRecord.Type] { get }

    /// views this view depends on - used to validate dependencies before rebuild
    static var dependsOnViews: [any ViewRecord.Type] { get }

    /// creates the view in the database (v1.0.0)
    static func createView(db: Database) throws

    /// rebuilds the view (drop + recreate) when dependencies change
    static func rebuild(db: Database) throws

    /// creates index optimizations for view queries (v1.0.1)
    static func createIndexes(db: Database) throws
}

// MARK: - Default Implementations

extension ViewRecord {
    static var dependsOnViews: [any ViewRecord.Type] { [] }

    static func createView(db: Database) throws {
        try db.create(view: databaseTableName, options: [.ifNotExists], as: viewDefinition)
    }

    static func rebuild(db: Database) throws {
        for tableDep in dependsOn {
            guard try db.tableExists(tableDep.databaseTableName) else {
                throw ViewError.missingTableDependency(
                    view: databaseTableName, table: tableDep.databaseTableName)
            }
        }

        for viewDep in dependsOnViews {
            guard try viewDep.exists(in: db) else {
                throw ViewError.missingViewDependency(
                    view: databaseTableName, dependency: viewDep.databaseTableName)
            }
        }

        if try exists(in: db) {
            try db.drop(view: databaseTableName)
        }
        try db.create(view: databaseTableName, as: viewDefinition)
    }

    static func createIndexes(db: Database) throws {
        // override in views that need supporting indexes
    }
}

// MARK: - View Management Extensions

extension ViewRecord {
    static func exists(in db: Database) throws -> Bool {
        try db.viewExists(databaseTableName)
    }

    static func drop(db: Database) throws {
        if try exists(in: db) {
            try db.drop(view: databaseTableName)
        }
    }

    static func validateDependencies(in db: Database) throws -> Bool {
        try dependsOn.allSatisfy { dependency in
            try db.tableExists(dependency.databaseTableName)
        }
    }
}

//
//  Migrations.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import GRDB

/// central registry for all database migrations. schema is created by iterating
/// the ordered record + view lists; GRDB ensures each migration runs once.
enum Migrations {
    static func register(
        with migrator: inout DatabaseMigrator,
        records: [any DatabaseRecord.Type],
        views: [any ViewRecord.Type]
    ) {
        registerV1_0_0(with: &migrator, records: records, views: views)
        registerV1_0_1(with: &migrator, records: records, views: views)
    }

    // MARK: - v1.0.0: initial schema (all tables + views)

    private static func registerV1_0_0(
        with migrator: inout DatabaseMigrator,
        records: [any DatabaseRecord.Type],
        views: [any ViewRecord.Type]
    ) {
        let name = DatabaseVersion(1, 0, 0).createMigrationName(description: "initial_schema")
        migrator.registerMigration(name) { db in
            for record in records {
                try record.createTable(db: db)
            }
            for view in views {
                try view.createView(db: db)
            }
        }
    }

    // MARK: - v1.0.1: index optimizations

    private static func registerV1_0_1(
        with migrator: inout DatabaseMigrator,
        records: [any DatabaseRecord.Type],
        views: [any ViewRecord.Type]
    ) {
        let name = DatabaseVersion(1, 0, 1).createMigrationName(description: "index_optimizations")
        migrator.registerMigration(name) { db in
            for record in records {
                try record.createIndexes(db: db)
            }
            for view in views {
                try view.createIndexes(db: db)
            }
        }
    }
}

//
//  Migrations.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import GRDB

/// central registry for all database migrations. schema is created by iterating
/// the ordered record + view lists; GRDB ensures each migration runs once.
///
/// **v1 is closed as of 2026-08-13.** Until then v1.0.0 and v1.0.1 were edited
/// in place and DEBUG wiped the database on any edit, which is what made the
/// whole schema free to move while nothing had shipped. That is over.
///
/// From here this file is **append-only**, per GRDB's usual rule:
///
/// - never edit `registerV1_0_0` or `registerV1_0_1`, and never edit an existing
///   record's `createTable`/`createIndexes` in a way that changes what those two
///   produce. Their checksums are what a shipped database is migrated against.
/// - a new column, table, view or index is a **new** `registerV1_0_2`-and-onward
///   migration doing its own `ALTER TABLE` / `CREATE`, added to `register`.
/// - a new record type still owns its `createTable`, and still goes in
///   `DatabaseClient.allRecords` so a fresh install builds it in v1.0.0 - but an
///   existing install only ever gets it from the new migration, so both paths
///   have to be written.
/// - dropping or renaming a column is a table rebuild, not an edit. Say so
///   before doing it.
///
/// Any schema change still gets flagged to the user before it is made.
enum Migrations {
    static func register(
        with migrator: inout DatabaseMigrator,
        records: [any DatabaseRecord.Type],
        views: [any ViewRecord.Type]
    ) {
        registerV1_0_0(with: &migrator, records: records, views: views)
        registerV1_0_1(with: &migrator, records: records, views: views)
    }

    // MARK: - v1.0.0: initial schema (all tables + views). CLOSED - do not edit

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

    // MARK: - v1.0.1: index optimizations. CLOSED - do not edit

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

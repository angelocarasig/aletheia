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
        registerV1_0_2(with: &migrator)
        registerV1_0_3(with: &migrator)
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

    // MARK: - v1.0.2: backfill series.updatedDate from real chapter publish dates. CLOSED - do not edit

    // series.updatedDate used to freeze at row-creation time forever. now that it
    // tracks the newest chapter's publishedDate going forward, existing rows need
    // one correction to match - series with no chapters are left alone, since
    // there is nothing to derive a date from
    //
    // table/column names are spelled out literally rather than through
    // SeriesRecord/ChapterRecord/OriginRecord's Columns - those track whatever
    // the record looks like today, but this migration is frozen to what the
    // schema looked like at v1.0.2. a later rename must not silently rewrite
    // history that already shipped
    private static func registerV1_0_2(
        with migrator: inout DatabaseMigrator
    ) {
        let name = DatabaseVersion(1, 0, 2).createMigrationName(
            description: "backfill_series_updatedDate")
        migrator.registerMigration(name) { db in
            try db.execute(
                sql: """
                    UPDATE series
                    SET updatedDate = (
                        SELECT MAX(c.publishedDate)
                        FROM chapter c
                        JOIN origin o ON o.id = c.originId
                        WHERE o.seriesId = series.id
                    )
                    WHERE EXISTS (
                        SELECT 1
                        FROM chapter c
                        JOIN origin o ON o.id = c.originId
                        WHERE o.seriesId = series.id
                    )
                    """)
        }
    }

    // MARK: - v1.0.3: series_recommendation, drop series.catalogId. CLOSED - do not edit

    // catalogId moves to series_recommendation, alongside the rail it was computed
    // for, so resolution identity and a computed result are never two things a
    // caller has to check separately. table/column names are spelled out
    // literally - same rule as v1.0.2 - this migration is frozen to what series
    // looked like at v1.0.3, and must not silently track a later rename
    //
    // foreign keys deferred: series_tracker, recommendation_impression and (once
    // this migration finishes) series_recommendation all reference series, and the
    // DROP TABLE step below would fail against every one of their rows otherwise
    private static func registerV1_0_3(
        with migrator: inout DatabaseMigrator
    ) {
        let name = DatabaseVersion(1, 0, 3).createMigrationName(
            description: "series_recommendation")
        migrator.registerMigration(name, foreignKeyChecks: .deferred) { db in
            try db.execute(
                sql: """
                    CREATE TABLE series_new (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        preferredTitleId INTEGER REFERENCES title(id) ON DELETE SET NULL,
                        preferredCoverId INTEGER REFERENCES cover(id) ON DELETE SET NULL,
                        preferredSynopsisId INTEGER REFERENCES metadata(id) ON DELETE SET NULL,
                        preferredClassificationId INTEGER REFERENCES metadata(id) ON DELETE SET NULL,
                        preferredPublicationId INTEGER REFERENCES metadata(id) ON DELETE SET NULL,
                        inLibrary BOOLEAN NOT NULL DEFAULT 0,
                        status TEXT NOT NULL DEFAULT 'planning',
                        addedDate DATETIME NOT NULL,
                        updatedDate DATETIME NOT NULL,
                        lastFetchedDate DATETIME NOT NULL,
                        lastReadDate DATETIME NOT NULL,
                        orientation TEXT NOT NULL,
                        showAllChapters BOOLEAN NOT NULL DEFAULT 0,
                        showHalfChapters BOOLEAN NOT NULL DEFAULT 1
                    )
                    """)

            try db.execute(
                sql: """
                    INSERT INTO series_new (
                        id, preferredTitleId, preferredCoverId, preferredSynopsisId,
                        preferredClassificationId, preferredPublicationId, inLibrary, status,
                        addedDate, updatedDate, lastFetchedDate, lastReadDate, orientation,
                        showAllChapters, showHalfChapters
                    )
                    SELECT
                        id, preferredTitleId, preferredCoverId, preferredSynopsisId,
                        preferredClassificationId, preferredPublicationId, inLibrary, status,
                        addedDate, updatedDate, lastFetchedDate, lastReadDate, orientation,
                        showAllChapters, showHalfChapters
                    FROM series
                    """)

            try db.execute(sql: "DROP TABLE series")
            try db.execute(sql: "ALTER TABLE series_new RENAME TO series")

            try db.create(index: "idx_series_inLibrary", on: "series", columns: ["inLibrary"])
            try db.create(
                index: "idx_series_addedDate_id", on: "series", columns: ["addedDate", "id"])
            try db.create(
                index: "idx_series_updatedDate_id", on: "series", columns: ["updatedDate", "id"])
            try db.create(
                index: "idx_series_lastReadDate_id", on: "series", columns: ["lastReadDate", "id"])

            try SeriesRecommendationRecord.createTable(db: db)
            try SeriesRecommendationRecord.createIndexes(db: db)
        }
    }
}

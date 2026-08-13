//
//  SeriesFTS5View.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import GRDB

internal struct SeriesFTS5View: ViewRecord {
    /// the series ID (maps to series.id)
    let rowid: Int64

    /// every title the series is known by (delimited with ' | ')
    let titles: String

    /// every supplier's synopsis (delimited with ' | ')
    let synopses: String

    /// tags (delimited with ' | ')
    let tags: String

    static var databaseTableName: String { "series_fts" }

    static let dependsOn: [any DatabaseRecord.Type] = [
        SeriesRecord.self,
        TitleRecord.self,
        MetadataRecord.self,
        TagRecord.self,
        SeriesTagRecord.self
    ]

    static var viewDefinition: SQLRequest<SeriesFTS5View> {
        // FTS5 virtual tables don't use SQLRequest
        // they're created differently via createView
        SQLRequest(sql: "SELECT rowid, titles, synopses, tags FROM \(databaseTableName)")
    }
}

// MARK: - Database Configuration

extension SeriesFTS5View {
    static func createView(db: Database) throws {
        // create FTS5 table (populated and maintained via triggers)
        try db.create(virtualTable: databaseTableName, options: [.ifNotExists], using: FTS5()) { t in
            // Unicode tokenizer with diacritic removal (for international titles)
            t.tokenizer = .unicode61(diacritics: .remove)

            // indexed columns for full-text search
            t.column("titles")
            t.column("synopses")
            t.column("tags")
        }

        // wrap trigger creation in savepoint for atomic rollback
        // if any trigger fails, all triggers are rolled back
        try db.inSavepoint {
            try createTriggers(db: db)
            return .commit
        }
    }

    private static func titlesSQL(for seriesId: String) -> String {
        """
        (SELECT COALESCE(GROUP_CONCAT(\(TitleRecord.Columns.value.name), ' | '), '')
         FROM \(TitleRecord.databaseTableName)
         WHERE seriesId = \(seriesId))
        """
    }

    // every supplier's synopsis, trackers included and unfiltered - a search bar
    // wants recall, and merge narrowing always confirms
    private static func synopsesSQL(for seriesId: String) -> String {
        """
        (SELECT COALESCE(GROUP_CONCAT(\(MetadataRecord.Columns.synopsis.name), ' | '), '')
         FROM \(MetadataRecord.databaseTableName)
         WHERE seriesId = \(seriesId))
        """
    }

    private static func tagsSQL(for seriesId: String) -> String {
        """
        (SELECT COALESCE(GROUP_CONCAT(displayName, ' | '), '')
         FROM \(TagRecord.databaseTableName)
         JOIN \(SeriesTagRecord.databaseTableName) ON \(TagRecord.databaseTableName).id = \(SeriesTagRecord.databaseTableName).tagId
         WHERE \(SeriesTagRecord.databaseTableName).seriesId = \(seriesId))
        """
    }

    private static func createTriggers(db: Database) throws {
        // series carries no indexed text of its own - the row is created empty and
        // filled in by the title/origin/tag triggers. nothing on series can dirty
        // the index, so there is deliberately no AFTER UPDATE ON series trigger.
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS \(databaseTableName)_series_ai
            AFTER INSERT ON \(SeriesRecord.databaseTableName)
            BEGIN
                INSERT INTO \(databaseTableName) (rowid, titles, synopses, tags)
                VALUES (NEW.id, '', '', '');
            END
            """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS \(databaseTableName)_series_ad
            AFTER DELETE ON \(SeriesRecord.databaseTableName)
            BEGIN
                DELETE FROM \(databaseTableName) WHERE rowid = OLD.id;
            END
            """)

        for (suffix, event, row) in [
            ("ai", "AFTER INSERT", "NEW"),
            ("au", "AFTER UPDATE OF \(TitleRecord.Columns.value.name)", "NEW"),
            ("ad", "AFTER DELETE", "OLD")
        ] {
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS \(databaseTableName)_title_\(suffix)
                \(event) ON \(TitleRecord.databaseTableName)
                BEGIN
                    UPDATE \(databaseTableName)
                    SET titles = \(titlesSQL(for: "\(row).seriesId"))
                    WHERE rowid = \(row).seriesId;
                END
                """)
        }

        for (suffix, event, row) in [
            ("ai", "AFTER INSERT", "NEW"),
            ("au", "AFTER UPDATE OF \(MetadataRecord.Columns.synopsis.name)", "NEW"),
            ("ad", "AFTER DELETE", "OLD")
        ] {
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS \(databaseTableName)_metadata_\(suffix)
                \(event) ON \(MetadataRecord.databaseTableName)
                BEGIN
                    UPDATE \(databaseTableName)
                    SET synopses = \(synopsesSQL(for: "\(row).seriesId"))
                    WHERE rowid = \(row).seriesId;
                END
                """)
        }

        for (suffix, event, row) in [
            ("ai", "AFTER INSERT", "NEW"),
            ("ad", "AFTER DELETE", "OLD")
        ] {
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS \(databaseTableName)_seriestag_\(suffix)
                \(event) ON \(SeriesTagRecord.databaseTableName)
                BEGIN
                    UPDATE \(databaseTableName)
                    SET tags = \(tagsSQL(for: "\(row).seriesId"))
                    WHERE rowid = \(row).seriesId;
                END
                """)
        }

        // trigger for tag displayName updates
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS \(databaseTableName)_tag_au
            AFTER UPDATE OF displayName ON \(TagRecord.databaseTableName)
            BEGIN
                UPDATE \(databaseTableName)
                SET tags = \(tagsSQL(for: "\(databaseTableName).rowid"))
                WHERE rowid IN (
                    SELECT seriesId FROM \(SeriesTagRecord.databaseTableName) WHERE tagId = NEW.id
                );
            END
            """)
    }

    static func rebuild(db: Database) throws {
        try db.execute(sql: "INSERT INTO \(databaseTableName)(\(databaseTableName)) VALUES('rebuild')")
    }

    // no indexes needed - FTS5 virtual table has its own indexing
}

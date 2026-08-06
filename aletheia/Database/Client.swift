//
//  Client.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import Foundation
import GRDB

final class DatabaseClient: Sendable {
    static let client = DatabaseClient()

    let reader: DatabaseReader
    let writer: DatabaseWriter

    private static let path: URL = Constants.Paths.database

    // schema creation order — FK targets must precede their referrers
    private static let allRecords: [any DatabaseRecord.Type] = [
        SeriesRecord.self,
        SourceRecord.self,
        ScanlatorRecord.self,
        AuthorRecord.self,
        TagRecord.self,
        CollectionRecord.self,
        OriginRecord.self,
        CoverRecord.self,
        TitleRecord.self,
        SeriesTagRecord.self,
        SeriesAuthorRecord.self,
        SeriesCollectionRecord.self,
        ChapterRecord.self,
        OriginScanlatorPriorityRecord.self,
    ]

    // views created after tables; view deps precede dependents
    private static let allViews: [any ViewRecord.Type] = [
        BestChapterView.self,
        EntryView.self,
        RichfulEntryView.self,
        SeriesFTS5View.self,
    ]

    private static var configuration: Configuration {
        var config = Configuration()
        config.label = "Aletheia"
        config.foreignKeysEnabled = true

        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous = NORMAL")        // keep — WAL pairing
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 2000")   // keep — sync-burst scar
            try db.execute(sql: "PRAGMA cache_size = -4000")          // keep — see reader note

            #if DEBUG
//            db.trace { print("[SQL]> \($0)") }
            #endif
        }

        #if DEBUG
        config.publicStatementArguments = true
        #endif

        return config
    }

    private init() {
        do {
            let pool = try DatabasePool(
                path: DatabaseClient.path.path(),
                configuration: DatabaseClient.configuration
            )

            var migrator = DatabaseMigrator()
            #if DEBUG
            // schema (v1.0.0) and indexes (v1.0.1) are edited in place during dev;
            // erase-on-change so those edits take effect without a manual wipe
            migrator.eraseDatabaseOnSchemaChange = true
            #endif
            Migrations.register(with: &migrator, records: DatabaseClient.allRecords, views: DatabaseClient.allViews)
            try migrator.migrate(pool)

            self.reader = pool
            self.writer = pool
        }
        catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}

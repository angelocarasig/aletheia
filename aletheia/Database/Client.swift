//
//  Client.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import Foundation
import GRDB

final class DatabaseClient: Sendable {
    // only here to satisfy the @Entry defaults in AppEnvironment, which the
    // bootstrapped tree never reads. the app path goes through open().
    // SwiftUI evaluates an environment default the moment a view declares the
    // property, so in a preview - where the container is not the app's - the
    // trap fired before any body ran. debug falls back to memory instead
    #if DEBUG
    static let client = (try? DatabaseClient()) ?? preview
    #else
    static let client = try! DatabaseClient()
    #endif

    let reader: DatabaseReader
    let writer: DatabaseWriter

    private static let path: URL = Constants.Paths.database

    // schema creation order - FK targets must precede their referrers
    private static let allRecords: [any DatabaseRecord.Type] = [
        SeriesRecord.self,
        SourceRecord.self,
        ScanlatorRecord.self,
        AuthorRecord.self,
        TagRecord.self,
        CollectionRecord.self,
        OriginRecord.self,
        // metadata references both origin and series_tracker, and cover/title
        // reference metadata, so the tracker table moves ahead of the pools
        SeriesTrackerRecord.self,
        MetadataRecord.self,
        CoverRecord.self,
        TitleRecord.self,
        SeriesTagRecord.self,
        SeriesAuthorRecord.self,
        SeriesCollectionRecord.self,
        ChapterRecord.self,
        OriginScanlatorPriorityRecord.self,
        SeriesLanguagePriorityRecord.self,
        ReadingEventRecord.self,
        ReadingSessionRecord.self,
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
            try db.execute(sql: "PRAGMA synchronous = NORMAL")        // keep - WAL pairing
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 2000")   // keep - sync-burst scar
            try db.execute(sql: "PRAGMA cache_size = -4000")          // keep - see reader note

            #if DEBUG
//            db.trace { print("[SQL]> \($0)") }
            #endif
        }

        #if DEBUG
        config.publicStatementArguments = true
        #endif

        return config
    }

    // throws rather than traps - a launch while the device is locked surfaces as
    // SQLITE_IOERR, and that has to reach the user as a retry, not a crash
    init() throws {
        let pool = try DatabasePool(
            path: DatabaseClient.path.path(),
            configuration: DatabaseClient.configuration
        )

        var migrator = DatabaseMigrator()
        #if DEBUG
        // v1 closed 2026-08-13 and migrations are append-only from here, so this
        // should no longer fire: a new migration is a new registration rather
        // than a changed checksum. it stays as the backstop for the one case it
        // still catches - an accidental edit to v1.0.0 or v1.0.1, which on a
        // device would be a corrupt migration and here is just a rebuild
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        Migrations.register(with: &migrator, records: DatabaseClient.allRecords, views: DatabaseClient.allViews)
        try migrator.migrate(pool)

        self.reader = pool
        self.writer = pool
    }

    #if DEBUG
    // previews and tests: the schema with nothing in it, no app group and no
    // file. a pool needs WAL companions on disk, so memory is a queue
    static let preview: DatabaseClient = try! DatabaseClient(inMemory: ())

    private init(inMemory: Void) throws {
        let queue = try DatabaseQueue(configuration: DatabaseClient.configuration)

        var migrator = DatabaseMigrator()
        Migrations.register(with: &migrator, records: DatabaseClient.allRecords, views: DatabaseClient.allViews)
        try migrator.migrate(queue)

        self.reader = queue
        self.writer = queue
    }
    #endif
}

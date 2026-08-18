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
    // bootstrapped tree never reads - the app path goes through open().
    // SwiftUI evaluates an environment default the moment a view declares the
    // property, so in a preview this trapped before any body ran; debug falls
    // back to memory instead
    #if DEBUG
        static let client = (try? DatabaseClient()) ?? preview
    #else
        static let client = try! DatabaseClient()
    #endif

    let reader: DatabaseReader
    let writer: DatabaseWriter

    private static let path: URL = Constants.Paths.database

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
        RecommendationImpressionRecord.self,
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
            try db.execute(sql: "PRAGMA synchronous = NORMAL")  // keep - WAL pairing
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 2000")  // keep - sync-burst scar
            try db.execute(sql: "PRAGMA cache_size = -4000")  // keep
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
            // deliberately off since 2026-08-15. v1.0.0 and v1.0.1 were reopened once
            // to take recommendation_impression and series.catalogId, which changed
            // their checksums - and with this on, that edit would have been absorbed
            // silently by a wipe, which is the opposite of what a reopened migration
            // should feel like
            //
            // the consequence is the point: a changed checksum now THROWS at launch,
            // so a schema edit has to be answered by deleting the app and letting the
            // database be rebuilt on purpose. turning this back on returns the
            // silence along with the convenience
            //
            // migrator.eraseDatabaseOnSchemaChange = true
        #endif
        Migrations.register(
            with: &migrator, records: DatabaseClient.allRecords, views: DatabaseClient.allViews)
        try migrator.migrate(pool)

        self.reader = pool
        self.writer = pool
    }

    #if DEBUG
        // DatabaseQueue, not DatabasePool - a pool needs WAL companion files on
        // disk, which an in-memory database doesn't have
        static let preview: DatabaseClient = try! DatabaseClient(inMemory: ())

        private init(inMemory: Void) throws {
            let queue = try DatabaseQueue(configuration: DatabaseClient.configuration)

            var migrator = DatabaseMigrator()
            Migrations.register(
                with: &migrator, records: DatabaseClient.allRecords, views: DatabaseClient.allViews)
            try migrator.migrate(queue)

            self.reader = queue
            self.writer = queue
        }
    #endif
}

//
//  Compositor+Persistence.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB

extension Compositor {
    struct Persistence: Sendable {
        private let database: DatabaseClient
        private let registry: Registry
        private let downloads: Downloads

        init(database: DatabaseClient, registry: Registry, downloads: Downloads) {
            self.database = database
            self.registry = registry
            self.downloads = downloads
        }

        // only caller is backup restore - needs a genuinely empty db, not one merged into
        func wipe() async throws {
            AppLog.shared.log("wipe starting", category: "wipe")

            await downloads.cancelAll()

            let deleted = try await database.writer.write { db -> Int in
                var total = 0
                for record in DatabaseClient.allRecords.reversed() {
                    total += try record.deleteAll(db)
                }
                return total
            }

            Keychain.sources.deleteAll()
            Keychain.trackers.deleteAll()

            await registry.seed()
            await downloads.sweep()

            AppLog.shared.log(
                "wipe complete - \(deleted) row(s) cleared, credentials cleared, sources reseeded",
                category: "wipe")
        }

        func clean() async {
            do {
                let deleted = try await database.writer.write { db in
                    // never-opened (lastReadDate still .distantPast), never picked a
                    // status (still .planning), and not in library - together mark a
                    // series as disposable
                    let never = Date.distantPast
                    return
                        try SeriesRecord
                        .filter(SeriesRecord.Columns.lastReadDate == never)
                        .filter(SeriesRecord.Columns.inLibrary == false)
                        .filter(SeriesRecord.Columns.status == Status.planning.rawValue)
                        .deleteAll(db)
                }
                AppLog.shared.log(
                    "cleaned \(deleted) unread series not in library", category: "clean")
            } catch {
                AppLog.shared.log("clean FAILED - \(error)", level: .error, category: "clean")
            }
        }
    }
}

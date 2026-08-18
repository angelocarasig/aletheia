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

        init(database: DatabaseClient) {
            self.database = database
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

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
                    // a series never opened in the reader still holds lastReadDate's
                    // .distantPast default, which is what marks it as disposable
                    try SeriesRecord
                        .filter(SeriesRecord.Columns.inLibrary == false)
                        .filter(SeriesRecord.Columns.lastReadDate == Date.distantPast)
                        .deleteAll(db)
                }
                AppLog.shared.log("cleaned \(deleted) unread series not in library", category: "clean")
            } catch {
                AppLog.shared.log("clean FAILED — \(error)", category: "clean")
            }
        }
    }
}

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
                    // .distantPast default, and status stays at .planning until you
                    // deliberately pick one - together they mark it as disposable.
                    // lastReadDate leads because it is the selective one with an
                    // index behind it; inLibrary covers two values and is not
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

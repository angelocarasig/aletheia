//
//  Compositor+SeriesRecommendations.swift
//  aletheia
//
//  Created by Angelo Carasig on 20/8/2026
//

import Foundation
import GRDB
import Tagged

extension Compositor {
    final class SeriesRecommendations: Sendable {
        private let database: DatabaseClient

        init(database: DatabaseClient) {
            self.database = database
        }

        // the one lookup a caller ever needs - a miss (nil) means "compute it",
        // never "check somewhere else"
        func fetch(seriesId: SeriesRecord.ID, packId: String) async -> SeriesRecommendationRecord? {
            do {
                return try await database.reader.read { db in
                    try SeriesRecommendationRecord
                        .filter(SeriesRecommendationRecord.Columns.seriesId == seriesId.rawValue)
                        .filter(SeriesRecommendationRecord.Columns.packId == packId)
                        .fetchOne(db)
                }
            } catch {
                AppLog.shared.log(
                    "series recommendation read failed - \(error)",
                    level: .error, category: "recommendations")
                return nil
            }
        }

        // upsert on (seriesId, packId) - a resolved-then-recomputed seed replaces
        // its own row rather than accumulating history, since only the current
        // answer is ever read
        @discardableResult
        func save(
            seriesId: SeriesRecord.ID,
            packId: String,
            catalogId: Int64?,
            fingerprint: String,
            rail: Data
        ) async -> SeriesRecommendationRecord? {
            do {
                return try await database.writer.write { db in
                    try db.execute(
                        sql: """
                            INSERT INTO \(SeriesRecommendationRecord.databaseTableName)
                                (seriesId, packId, catalogId, fingerprint, rail, computedDate)
                            VALUES (?, ?, ?, ?, ?, ?)
                            ON CONFLICT(seriesId, packId) DO UPDATE SET
                                catalogId = excluded.catalogId,
                                fingerprint = excluded.fingerprint,
                                rail = excluded.rail,
                                computedDate = excluded.computedDate
                            """,
                        arguments: [
                            seriesId.rawValue, packId, catalogId, fingerprint, rail, Date.now,
                        ])

                    return try SeriesRecommendationRecord
                        .filter(SeriesRecommendationRecord.Columns.seriesId == seriesId.rawValue)
                        .filter(SeriesRecommendationRecord.Columns.packId == packId)
                        .fetchOne(db)
                }
            } catch {
                AppLog.shared.log(
                    "series recommendation write failed - \(error)",
                    level: .error, category: "recommendations")
                return nil
            }
        }
    }
}

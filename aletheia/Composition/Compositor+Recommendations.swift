//
//  Compositor+Recommendations.swift
//  aletheia
//
//  Created by Angelo Carasig on 20/8/2026
//

import Foundation
import GRDB
import Tagged

extension Compositor {
    final class Recommendations: Sendable {
        private let database: DatabaseClient

        // a cache entry this old is stale regardless of fingerprint - a
        // scorer/blend change alone (same seed, same pack, better answer)
        // never touches the fingerprint, so without this an entry could
        // otherwise serve the same answer forever
        private static let ttl: TimeInterval = 3 * 24 * 60 * 60

        init(database: DatabaseClient) {
            self.database = database
        }

        // startup job, same shape as assets.sweep()/downloads.sweep()
        func sweep() {
            guard !Constants.App.isPreview else { return }
            Task { [database] in
                let threshold = Date.now.addingTimeInterval(-Self.ttl)
                do {
                    let removed = try await database.writer.write { db in
                        try SeriesRecommendationRecord
                            .filter(SeriesRecommendationRecord.Columns.computedDate < threshold)
                            .deleteAll(db)
                    }
                    AppLog.shared.log(
                        "swept \(removed) stale recommendation(s)", category: "recommendations")
                } catch {
                    AppLog.shared.log(
                        "recommendation sweep FAILED - \(error)", level: .error,
                        category: "recommendations")
                }
            }
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

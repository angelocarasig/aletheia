//
//  Compositor+Impressions.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Foundation
import GRDB
import Tagged

extension Compositor {
    final class Impressions: Sendable {
        private let database: DatabaseClient
        private let writer: Writer

        init(database: DatabaseClient) {
            self.database = database
            self.writer = Writer(database: database)
        }

        static func batch() -> String { UUID().uuidString }

        // "shown" means visible on screen, NOT present in the rail's backing array -
        // the rail holds twenty and about three are visible at once. logging the
        // array would merge "never seen" and "seen and passed over"
        func shown(
            _ recommendation: Recommendation,
            rank: Int,
            batchId: String,
            seed: SeriesRecord.ID,
            seedCatalogId: CatalogID?,
            modelVersion: String,
            alreadyInLibrary: Bool,
            surface: RecommendationImpressionRecord.Surface = .detailsRail
        ) {
            let record = RecommendationImpressionRecord(
                catalogId: Int64(recommendation.catalogId.rawValue),
                catalogTitle: recommendation.title,
                seedSeriesId: seed,
                seedCatalogId: seedCatalogId.map { Int64($0.rawValue) },
                batchId: batchId,
                rank: rank,
                surface: surface,
                modelVersion: modelVersion,
                score: Double(recommendation.score),
                confidence: Double(recommendation.confidence),
                blockTag: Double(recommendation.blocks.tag),
                blockEmbedding: Double(recommendation.blocks.embedding),
                blockEra: Double(recommendation.blocks.era),
                alreadyInLibrary: alreadyInLibrary)

            Task { await writer.enqueue(record) }
        }

        func tapped(catalogId: CatalogID, batchId: String) {
            Task { await writer.tapped(catalogId: Int64(catalogId.rawValue), batchId: batchId) }
        }

        // which catalogue rows the reader already owns, so an impression can say
        // whether it was suggesting something new. read once per result set - a
        // rail draws twenty cards and this is one query
        //
        // only series with a resolved series_recommendation row are here.
        // Compositor.SeriesRecommendations.save is what writes resolution
        // identity in the normal recommend flow; a backup-restored series sets
        // inLibrary directly (LibraryBackupRestorer) and is not counted here
        // until its next Details open resolves the seed
        func owned() async -> Set<CatalogID> {
            do {
                return try await database.reader.read { db in
                    let ids = try Int64.fetchAll(
                        db,
                        sql: """
                            SELECT rc.\(SeriesRecommendationRecord.Columns.catalogId.name)
                            FROM \(SeriesRecommendationRecord.databaseTableName) rc
                            JOIN \(SeriesRecord.databaseTableName) s
                              ON s.\(SeriesRecord.Columns.id.name) = rc.\(SeriesRecommendationRecord.Columns.seriesId.name)
                            WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1
                              AND rc.\(SeriesRecommendationRecord.Columns.catalogId.name) IS NOT NULL
                            """)
                    return Set(ids.map { CatalogID(rawValue: Int32($0)) })
                }
            } catch {
                // an empty set understates ownership rather than inventing it,
                // and the column is a snapshot either way
                AppLog.shared.log(
                    "owned set unavailable - \(error)",
                    level: .error, category: "impressions")
                return []
            }
        }
    }
}

// MARK: - Writer

extension Compositor.Impressions {
    // cards cross the visibility threshold in bursts - a flick through a rail is
    // a dozen in under a second - so writes are buffered and flushed as one
    // transaction instead of one per card
    fileprivate actor Writer {
        private let database: DatabaseClient
        private var pending: [RecommendationImpressionRecord] = []
        private var written: Set<String> = []
        private var flush: Task<Void, Never>?

        private enum Limits {
            static let window: Duration = .milliseconds(400)
            static let max = 64
        }

        init(database: DatabaseClient) {
            self.database = database
        }

        func enqueue(_ record: RecommendationImpressionRecord) {
            let key = "\(record.batchId)/\(record.catalogId)"
            guard !written.contains(key) else { return }
            written.insert(key)
            pending.append(record)

            if pending.count >= Limits.max {
                flush?.cancel()
                Task { await self.drain() }
                return
            }
            guard flush == nil else { return }
            flush = Task { [weak self] in
                // a coalescing window, not a delay waiting on state - the buffer is
                // complete whenever it's read, this only decides how often
                try? await Task.sleep(for: Limits.window)
                await self?.drain()
            }
        }

        private func drain() async {
            flush = nil
            guard !pending.isEmpty else { return }
            let batch = pending
            pending = []
            do {
                try await database.writer.write { db in
                    for var record in batch { try record.insert(db) }
                }
                AppLog.shared.log(
                    "shown \(batch.count) - \(batch.map { "\($0.rank):\($0.catalogTitle.prefix(18))" }.joined(separator: ", "))",
                    category: "impressions")
            } catch {
                // dropped rather than retried - an impression is evidence, not
                // state, and a retry here would queue behind writes the reader is
                // actually waiting on
                AppLog.shared.log(
                    "dropped \(batch.count) impression(s) - \(error)",
                    level: .error, category: "impressions")
            }
        }

        func tapped(catalogId: Int64, batchId: String) async {
            // must drain first - a tap inside the coalescing window would otherwise
            // update a row that has not been inserted yet and silently do nothing
            await drain()
            do {
                try await database.writer.write { db in
                    try db.execute(
                        sql: """
                            UPDATE \(RecommendationImpressionRecord.databaseTableName)
                            SET \(RecommendationImpressionRecord.Columns.tappedDate.name) = ?
                            WHERE \(RecommendationImpressionRecord.Columns.batchId.name) = ?
                              AND \(RecommendationImpressionRecord.Columns.catalogId.name) = ?
                              AND \(RecommendationImpressionRecord.Columns.tappedDate.name) IS NULL
                            """, arguments: [Date.now, batchId, catalogId])
                    AppLog.shared.log(
                        "tapped \(catalogId) - \(db.changesCount) row(s) updated",
                        category: "impressions")
                }
            } catch {
                AppLog.shared.log(
                    "tap not recorded - \(error)",
                    level: .error, category: "impressions")
            }
        }

    }
}

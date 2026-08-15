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
    // what the recommender actually put in front of the reader, and whether it
    // was acted on. nothing else in the database can answer that: every other
    // stage of the funnel - added, read, completed, dropped - is already a fact
    // about a series the reader has, and those only exist once a recommendation
    // has already worked
    //
    // deliberately not a view model concern. a rail is rendered from three
    // different screens' worth of state and a view model that owned this would
    // record what IT knew rather than what was shown, which is the same class of
    // error as counting an array instead of counting a screen
    final class Impressions: Sendable {
        private let database: DatabaseClient
        private let writer: Writer

        init(database: DatabaseClient) {
            self.database = database
            self.writer = Writer(database: database)
        }

        // one render of a rail. every card shown under it belongs to this id, so
        // the set the reader chose between is recoverable - three rows without it
        // are three unrelated events rather than one choice
        static func batch() -> String { UUID().uuidString }

        // a card became visible. NOT a card that entered the array - the rail
        // holds twenty and about three are on screen, so logging the array would
        // put "never seen" and "seen and passed over" back into one bucket, which
        // is the entire reason this table exists
        func shown(_ recommendation: Recommendation,
                   rank: Int,
                   batchId: String,
                   seed: SeriesRecord.ID,
                   seedCatalogId: CatalogID?,
                   modelVersion: String,
                   alreadyInLibrary: Bool,
                   surface: RecommendationImpressionRecord.Surface = .detailsRail) {
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

        // the reader opened it. keyed by what the caller already has rather than
        // by row id, so nothing has to be threaded back out of the write
        func tapped(catalogId: CatalogID, batchId: String) {
            Task { await writer.tapped(catalogId: Int64(catalogId.rawValue), batchId: batchId) }
        }

        // the seed's catalogue row, kept so a recommendation shown today can be
        // joined to a series added next week. the recommender resolves this on
        // every rail and used to discard it; writing it only when it CHANGES
        // keeps an unchanged series out of the writer queue entirely
        func stamp(catalogId: CatalogID?, for series: SeriesRecord.ID) {
            guard let catalogId else { return }
            Task { await writer.stamp(catalogId: Int64(catalogId.rawValue), for: series) }
        }

        // which catalogue rows the reader already owns, so an impression can say
        // whether it was suggesting something new. read once per result set - a
        // rail draws twenty cards and this is one query
        //
        // only stamped series are here, which is exactly right rather than a gap:
        // Details is the only place inLibrary is ever set, and every Details open
        // resolves the seed - so a series can only enter the library by way of the
        // screen that stamps it
        func owned() async -> Set<CatalogID> {
            do {
                return try await database.reader.read { db in
                    let ids = try Int64.fetchAll(db, sql: """
                        SELECT \(SeriesRecord.Columns.catalogId.name)
                        FROM \(SeriesRecord.databaseTableName)
                        WHERE \(SeriesRecord.Columns.inLibrary.name) = 1
                          AND \(SeriesRecord.Columns.catalogId.name) IS NOT NULL
                        """)
                    return Set(ids.map { CatalogID(rawValue: Int32($0)) })
                }
            } catch {
                // an empty set understates ownership rather than inventing it,
                // and the column is a snapshot either way
                AppLog.shared.log("owned set unavailable - \(error)",
                                  level: .error, category: "impressions")
                return []
            }
        }
    }
}

// MARK: - Writer

private extension Compositor.Impressions {
    // cards cross the visibility threshold in bursts - a flick through a rail is
    // a dozen in under a second - and one transaction each would be a dozen
    // writer-queue entries competing with whatever else is running. buffered and
    // flushed as one
    //
    // the dedupe is per batch, not global: the same card scrolled off and back on
    // is one impression for that render, and a genuinely new render gets a new
    // batch id and is allowed to record it again
    actor Writer {
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
                // a coalescing window, not a delay waiting on state: the buffer is
                // complete whenever it is read, and this only decides how often
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
                // success has to say so. a table that only logs failure cannot be
                // told apart from one nothing ever calls, which is how a feature
                // ships, gets documented as shipped, and never once runs
                AppLog.shared.log(
                    "shown \(batch.count) - \(batch.map { "\($0.rank):\($0.catalogTitle.prefix(18))" }.joined(separator: ", "))",
                    category: "impressions")
            } catch {
                // an impression is evidence, not state - losing one costs a row in
                // an analysis nobody is running yet, and retrying would put a
                // failing write in front of everything the reader IS waiting for
                AppLog.shared.log("dropped \(batch.count) impression(s) - \(error)",
                                  level: .error, category: "impressions")
            }
        }

        func tapped(catalogId: Int64, batchId: String) async {
            // ahead of the update, or a tap inside the coalescing window updates a
            // row that has not been inserted yet and silently does nothing
            await drain()
            do {
                try await database.writer.write { db in
                    try db.execute(sql: """
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
                AppLog.shared.log("tap not recorded - \(error)",
                                  level: .error, category: "impressions")
            }
        }

        func stamp(catalogId: Int64, for series: SeriesRecord.ID) async {
            do {
                try await database.writer.write { db in
                    try db.execute(sql: """
                        UPDATE \(SeriesRecord.databaseTableName)
                        SET \(SeriesRecord.Columns.catalogId.name) = ?
                        WHERE \(SeriesRecord.Columns.id.name) = ?
                          AND (\(SeriesRecord.Columns.catalogId.name) IS NULL
                               OR \(SeriesRecord.Columns.catalogId.name) <> ?)
                        """, arguments: [catalogId, series.rawValue, catalogId])
                    // 0 changed is the ordinary case - it is already stamped
                    if db.changesCount > 0 {
                        AppLog.shared.log("stamped series \(series.rawValue) as catalog \(catalogId)",
                                          category: "impressions")
                    }
                }
            } catch {
                AppLog.shared.log("catalogId not stamped - \(error)",
                                  level: .error, category: "impressions")
            }
        }
    }
}

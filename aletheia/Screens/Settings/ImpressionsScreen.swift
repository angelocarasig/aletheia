//
//  ImpressionsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import GRDB
import SwiftUI

// what the recommender has actually shown, and what came of it. a read-only
// window onto recommendation_impression, which is otherwise only legible by
// pulling the database off the device
//
// deliberately shows counts beside every rate. at these volumes a percentage on
// its own is theatre - "25% tap rate" is one tap out of four - and a debug
// surface that reads as a finding is worse than one that reads as a count
struct ImpressionsScreen: View {
    @Environment(\.database) private var database
    @Environment(\.dimensions) private var dimensions

    @State private var model = Model()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                if model.total == 0 {
                    ContentUnavailableView(
                        "Nothing recorded yet",
                        systemImage: "eye.slash",
                        description: Text("Open a series with a Similar Titles rail and scroll it.")
                    )
                    .padding(.top, dimensions.spacing.space48)
                } else {
                    Totals
                    Funnel
                    Positions
                    Batches
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(database) }
        .refreshable { await model.load(database) }
    }

    // MARK: sections

    private var Totals: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Recorded")

            FlowLayout(spacing: dimensions.spacing.space8) {
                Stat("Impressions", model.total)
                // a card seen in two separate renders is two impressions and one
                // recommendation. counting rows measures viewings, which is a
                // different question and usually not the one being asked
                Stat("Distinct titles", model.distinct)
                Stat("Rails", model.batches)
                Stat("Seeds", model.seeds)
            }
        }
    }

    private var Funnel: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("What came of it")

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Line("Shown", "\(model.total)")
                Line(
                    "Tapped", "\(model.tapped) of \(model.total)\(rate(model.tapped, model.total))")
                // the payoff of series.catalogId: a tapped recommendation whose
                // catalogue row later appears in the library is a conversion that
                // nothing could express before the column existed
                Line("Added to library", "\(model.converted) of \(model.tapped)")
                Line("Already owned when shown", "\(model.owned) of \(model.total)")
            }
        }
    }

    private var Positions: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("By position")

            // whether rank alone drives taps is the question impressions exist to
            // answer, and it needs far more rows than this to answer honestly.
            // shown anyway because the shape is visible long before the number is
            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                ForEach(model.positions, id: \.rank) { row in
                    HStack(spacing: dimensions.spacing.space12) {
                        Text("\(row.rank)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)

                        GeometryReader { proxy in
                            let fraction =
                                model.widest > 0
                                ? Double(row.shown) / Double(model.widest) : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(.primary.opacity(0.08))
                                Capsule().fill(.brand)
                                    .frame(width: proxy.size.width * fraction)
                            }
                        }
                        .frame(height: 6)

                        Text(
                            row.tapped > 0 ? "\(row.shown) - \(row.tapped) tapped" : "\(row.shown)"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.tapped > 0 ? .primary : .secondary)
                        .frame(width: 110, alignment: .leading)
                    }
                }
            }
        }
    }

    private var Batches: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Recent rails")

            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                ForEach(model.recent, id: \.batchId) { row in
                    VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                        Text(row.seedTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text(
                            "\(row.shown) shown\(row.tapped > 0 ? ", \(row.tapped) tapped" : "") · \(row.modelVersion)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        LiveRelativeText(date: row.at)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: pieces

    private func Stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
            Text("\(value)")
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(0.05))
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
    }

    private func Line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer(minLength: dimensions.spacing.space12)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func rate(_ part: Int, _ whole: Int) -> String {
        guard whole > 0, part > 0 else { return "" }
        return
            "  (\((Double(part) / Double(whole)).formatted(.percent.precision(.fractionLength(0)))))"
    }
}

// MARK: - Model

extension ImpressionsScreen {
    @MainActor
    @Observable
    final class Model {
        private(set) var total = 0
        private(set) var distinct = 0
        private(set) var batches = 0
        private(set) var seeds = 0
        private(set) var tapped = 0
        private(set) var converted = 0
        private(set) var owned = 0
        private(set) var positions: [Position] = []
        private(set) var recent: [Batch] = []

        var widest: Int { positions.map(\.shown).max() ?? 0 }

        struct Position {
            let rank: Int
            let shown: Int
            let tapped: Int
        }
        struct Batch {
            let batchId: String
            let seedTitle: String
            let shown: Int
            let tapped: Int
            let modelVersion: String
            let at: Date
        }

        private enum Limits {
            static let rails = 12
            static let ranks = 20
        }

        func load(_ database: DatabaseClient) async {
            let table = RecommendationImpressionRecord.databaseTableName
            do {
                let loaded = try await database.reader.read { db -> (Model.Snapshot) in
                    let summary = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT count(*) AS total,
                                   count(DISTINCT catalogId) AS distinct_titles,
                                   count(DISTINCT batchId) AS batches,
                                   count(DISTINCT seedSeriesId) AS seeds,
                                   sum(tappedDate IS NOT NULL) AS tapped,
                                   sum(alreadyInLibrary) AS owned
                            FROM \(table)
                            """)

                    // a tap that later appears in the library. the join is on
                    // series.catalogId, which is the whole reason that column
                    // exists - without it this row could not be written
                    let converted =
                        try Int.fetchOne(
                            db,
                            sql: """
                                SELECT count(DISTINCT i.catalogId)
                                FROM \(table) i
                                JOIN \(SeriesRecord.databaseTableName) s
                                  ON s.\(SeriesRecord.Columns.catalogId.name) = i.catalogId
                                 AND s.\(SeriesRecord.Columns.inLibrary.name) = 1
                                WHERE i.tappedDate IS NOT NULL
                                """) ?? 0

                    let ranks = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT rank, count(*) AS shown, sum(tappedDate IS NOT NULL) AS tapped
                            FROM \(table) WHERE rank < ?
                            GROUP BY rank ORDER BY rank
                            """, arguments: [Limits.ranks])

                    let rails = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT i.batchId,
                                   i.modelVersion,
                                   count(*) AS shown,
                                   sum(i.tappedDate IS NOT NULL) AS tapped,
                                   min(i.occurredDate) AS at,
                                   COALESCE(t.value, 'Series ' || i.seedSeriesId) AS seedTitle
                            FROM \(table) i
                            LEFT JOIN \(SeriesRecord.databaseTableName) s ON s.id = i.seedSeriesId
                            LEFT JOIN \(TitleRecord.databaseTableName) t ON t.id = s.preferredTitleId
                            GROUP BY i.batchId
                            ORDER BY at DESC LIMIT ?
                            """, arguments: [Limits.rails])

                    return Snapshot(
                        summary: summary, converted: converted,
                        ranks: ranks, rails: rails)
                }
                apply(loaded)
            } catch {
                AppLog.shared.log(
                    "impression insights unavailable - \(error)",
                    level: .error, category: "impressions")
            }
        }

        struct Snapshot: Sendable {
            let summary: Row?
            let converted: Int
            let ranks: [Row]
            let rails: [Row]
        }

        private func apply(_ s: Snapshot) {
            total = s.summary?["total"] ?? 0
            distinct = s.summary?["distinct_titles"] ?? 0
            batches = s.summary?["batches"] ?? 0
            seeds = s.summary?["seeds"] ?? 0
            tapped = s.summary?["tapped"] ?? 0
            owned = s.summary?["owned"] ?? 0
            converted = s.converted
            positions = s.ranks.map {
                Position(rank: $0["rank"], shown: $0["shown"], tapped: $0["tapped"] ?? 0)
            }
            recent = s.rails.map {
                Batch(
                    batchId: $0["batchId"], seedTitle: $0["seedTitle"],
                    shown: $0["shown"], tapped: $0["tapped"] ?? 0,
                    modelVersion: $0["modelVersion"], at: $0["at"])
            }
        }
    }
}

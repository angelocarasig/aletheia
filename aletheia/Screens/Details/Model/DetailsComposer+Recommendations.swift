//
//  DetailsComposer+Recommendations.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation
import Observation
import Tagged

extension DetailsComposer {
    @MainActor
    @Observable
    final class Recommendations: DetailsApplying {
        private(set) var phase: LoadPhase = .pending
        private(set) var results: [Recommendation] = []

        // kept though nothing renders it yet - the difference between "the
        // model was wrong" and "this series had four usable tags"
        private(set) var seed: Seed?

        // handed to the view rather than assembled by it - a rail knows what
        // it drew but nothing about which series it drew for, so a view that
        // guessed would record its own state instead of the screen's
        private(set) var context: ImpressionContext?

        @ObservationIgnored private var payload: Payload?
        @ObservationIgnored private var running: Task<Void, Never>?
        @ObservationIgnored private let recommender: Recommender
        @ObservationIgnored private let impressions: Compositor.Impressions
        @ObservationIgnored private let seriesRecommendations: Compositor.SeriesRecommendations
        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        init(
            recommender: Recommender,
            impressions: Compositor.Impressions,
            seriesRecommendations: Compositor.SeriesRecommendations
        ) {
            self.recommender = recommender
            self.impressions = impressions
            self.seriesRecommendations = seriesRecommendations
        }

        struct ImpressionContext: Equatable {
            let batchId: String
            let series: SeriesRecord.ID
            let seedCatalogId: CatalogID?
            let modelVersion: String
            // resolved once per result set, not per card - a rail draws twenty
            // and this is one query
            let owned: Set<CatalogID>
        }

        func apply(_ stored: Stored) {
            seriesId = SeriesRecord.ID(rawValue: stored.entry.seriesId)

            // the whole title pool votes, not just the display title - an
            // earlier version took the first name that matched anything and
            // resolved the wrong series doing it
            var next = Payload(
                titles: stored.titles.map(\.value),
                tags: Series.split(stored.entry.tags)
            )
            // a MangaBaka link's remoteId IS the catalogue id, so a linked
            // series resolves exactly and skips name matching entirely
            if let linked = stored.trackers.first(where: { $0.tracker == .mangaBaka }) {
                next.catalogId = CatalogID(rawValue: Int32(linked.remoteId))
            }

            // the observation fires on every progress tick while reading; this
            // query is 53ms, so the guard is what stops it running per page turn
            guard next != payload else { return }
            payload = next
            load(next)
        }

        private func load(_ payload: Payload) {
            running?.cancel()
            phase = .pending
            running = Task { [recommender, impressions, seriesRecommendations, seriesId] in
                guard let seriesId else { return }
                let descriptor = await recommender.descriptor

                if let cached = await seriesRecommendations.fetch(
                    seriesId: seriesId, packId: descriptor.slug),
                    cached.fingerprint == payload.fingerprint,
                    let decoded = try? JSONDecoder().decode(
                        [Recommendation].self, from: cached.rail)
                {
                    guard !Task.isCancelled else { return }
                    results = decoded
                    phase = decoded.isEmpty ? .empty : .content
                    return
                }

                do {
                    let set = try await recommender.recommend(
                        payload,
                        ceiling: Self.ceiling,
                        formats: CatalogFormat.comics,
                        limit: Self.limit)
                    guard !Task.isCancelled else { return }

                    // context must finish building before results is set, and both
                    // set together - a card already on screen by the time context
                    // arrives never changes visibility again, so it would never
                    // be recorded. that would silently drop exactly the
                    // above-the-fold cards, the opposite of what this exists to fix
                    let owned = await impressions.owned()
                    guard !Task.isCancelled else { return }
                    let next = ImpressionContext(
                        batchId: Compositor.Impressions.batch(),
                        series: seriesId,
                        seedCatalogId: set.seedCatalogId,
                        modelVersion: "\(descriptor.slug)/format\(descriptor.formatVersion)",
                        owned: owned)

                    seed = set.seed
                    context = next
                    results = set.results
                    phase = set.results.isEmpty ? .empty : .content

                    // the cache is what stamps resolution identity now - a
                    // background write, not on the critical path to rendering
                    if let encoded = try? JSONEncoder().encode(set.results) {
                        await seriesRecommendations.save(
                            seriesId: seriesId,
                            packId: descriptor.slug,
                            catalogId: set.seedCatalogId.map { Int64($0.rawValue) },
                            fingerprint: payload.fingerprint,
                            rail: encoded)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    // no retry - a build with no model is the ordinary case on a
                    // fresh checkout, and none of these clear by trying again
                    results = []
                    phase = .empty
                    AppLog.shared.log(
                        "recommendations unavailable - \(error)",
                        category: "recommender")
                }
            }
        }

        // fixed rather than derived from the series or the adult gate - decided
        // 2026-08-14. nothing above suggestive surfaces here, so an explicit
        // series gets recommendations unlike itself and roughly a third of the
        // catalogue is unreachable, both accepted deliberately. also why these
        // covers are never blurred: nothing adult can appear
        static let ceiling: ContentCeiling = .suggestive
        static let limit = 20
    }
}

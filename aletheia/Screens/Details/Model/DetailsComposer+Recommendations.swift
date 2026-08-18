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

        // how the seed was arrived at, kept because it is the difference between
        // "the model was wrong" and "this series had four usable tags". nothing
        // renders it yet; it is what a debug surface would read
        private(set) var seed: Seed?

        // everything a card needs to record that it was seen, minted once per
        // result set. the view is handed this rather than assembling it: a rail
        // knows what it drew and nothing about which series it drew for, and a
        // view that guessed would record its own state instead of the screen's
        private(set) var context: ImpressionContext?

        @ObservationIgnored private var payload: Payload?
        @ObservationIgnored private var running: Task<Void, Never>?
        @ObservationIgnored private let recommender: Recommender
        @ObservationIgnored private let impressions: Compositor.Impressions
        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        init(recommender: Recommender, impressions: Compositor.Impressions) {
            self.recommender = recommender
            self.impressions = impressions
        }

        struct ImpressionContext: Equatable {
            let batchId: String
            let series: SeriesRecord.ID
            let seedCatalogId: CatalogID?
            let modelVersion: String
            // resolved once per result set rather than per card: a rail draws
            // twenty and this is one query
            let owned: Set<CatalogID>
        }

        // from DetailsApplying
        func apply(_ stored: Stored) {
            seriesId = SeriesRecord.ID(rawValue: stored.entry.seriesId)

            // the whole title pool votes, not just the display title - the
            // reference implementation took the first name that matched anything
            // and resolved the wrong series doing it
            var next = Payload(
                titles: stored.titles.map(\.value),
                tags: Series.split(stored.entry.tags)
            )
            // tier 0: a MangaBaka link's remoteId IS the catalogue id, so a
            // linked series resolves exactly and skips name matching entirely
            if let linked = stored.trackers.first(where: { $0.tracker == .mangaBaka }) {
                next.catalogId = CatalogID(rawValue: Int32(linked.remoteId))
            }

            // the observation fires on every progress tick while reading. the
            // query is 53ms and the answer cannot change unless the payload does,
            // so this guard is what stops it running per page turn
            guard next != payload else { return }
            payload = next
            load(next)
        }

        private func load(_ payload: Payload) {
            running?.cancel()
            phase = .pending
            running = Task { [recommender, impressions, seriesId] in
                do {
                    let set = try await recommender.recommend(
                        payload,
                        ceiling: Self.ceiling,
                        formats: CatalogFormat.comics,
                        limit: Self.limit)
                    guard !Task.isCancelled else { return }

                    // built BEFORE the results are published, and published with
                    // them in one step. every await here is a suspension the rail
                    // can render across - and a card that is already on screen
                    // when the context arrives never changes visibility again, so
                    // it would never be recorded. that loses exactly the cards
                    // visible without scrolling, which is the opposite of the
                    // exposure bias this is here to remove
                    var next: ImpressionContext?
                    if let seriesId {
                        let descriptor = await recommender.descriptor
                        let owned = await impressions.owned()
                        guard !Task.isCancelled else { return }
                        next = ImpressionContext(
                            // one per result set, so a batch means "the group you
                            // chose between" rather than "one time you looked"
                            batchId: Compositor.Impressions.batch(),
                            series: seriesId,
                            seedCatalogId: set.seedCatalogId,
                            modelVersion: "\(descriptor.slug)/format\(descriptor.formatVersion)",
                            owned: owned)
                        // the seed's catalogue row is resolved on every rail and
                        // was being discarded. keeping it is what lets a
                        // recommendation shown today be joined to a series added
                        // next week
                        impressions.stamp(catalogId: set.seedCatalogId, for: seriesId)
                    }

                    seed = set.seed
                    context = next
                    results = set.results
                    phase = set.results.isEmpty ? .empty : .content
                } catch {
                    guard !Task.isCancelled else { return }
                    // a build with no model is the ordinary case on a fresh
                    // checkout, and this section simply is not there. it carries
                    // no retry because none of these clear by trying again
                    results = []
                    phase = .empty
                    AppLog.shared.log(
                        "recommendations unavailable - \(error)",
                        category: "recommender")
                }
            }
        }

        // fixed rather than derived from the series or from the adult gate.
        // decided 2026-08-14: nothing above suggestive is ever surfaced here, so
        // an explicit series gets recommendations unlike itself and roughly a
        // third of the catalogue is unreachable - both accepted deliberately.
        // it is also why these covers are not blurred: nothing adult can appear
        static let ceiling: ContentCeiling = .suggestive
        static let limit = 20
    }
}

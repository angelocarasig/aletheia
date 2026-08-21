//
//  OrihimeRecommender.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation
import Tagged

// v02's adapter. same actor-per-load-once shape as V01Recommender - the only
// mutable state is whether the pack has loaded yet
//
// this phase only answers the resolved path (a catalogId link, or a title
// that resolves via the pack's own alias table) against the precomputed
// rails table. an unresolved seed with no live-compute path yet - the next
// phase - returns no results rather than guessing, the same "an addition to
// a screen, never load-bearing" degrade every recommender already follows
actor OrihimeRecommender: RecommenderService {
    private struct Loaded {
        let bundle: OrihimeBundle
        let rails: OrihimeRails
        let aliasIndex: OrihimeAliasIndex
        let tagVocabulary: OrihimeTagVocabulary
        let display: OrihimeDisplay?
    }

    private var loaded: Loaded?
    private var failure: RecommenderError?
    private let source: OrihimeBundle.Source

    init(source: OrihimeBundle.Source) {
        self.source = source
    }

    var descriptor: RecommenderDescriptor {
        get async {
            guard let state = try? state() else {
                return RecommenderDescriptor(
                    slug: "orihime", name: "Content v02",
                    formatVersion: 0, titleCount: 0,
                    encodesText: true, hasMetadata: false)
            }
            return RecommenderDescriptor(
                slug: "orihime",
                name: "Content v02",
                formatVersion: state.bundle.manifest.packSchema,
                titleCount: state.bundle.manifest.corpus.titles,
                encodesText: true,
                hasMetadata: state.display != nil)
        }
    }

    func warm() async {
        _ = try? state()
    }

    func recommend(
        _ payload: Payload,
        ceiling: ContentCeiling,
        formats: Set<CatalogFormat>,
        limit: Int
    ) async throws -> RecommendationSet {
        let state = try state()
        let seed = resolve(payload, in: state)

        guard let row = seed.row else {
            return RecommendationSet(seed: seed, seedCatalogId: nil, wTagEff: 0, used: 0, results: [])
        }
        let seedCatalogId = catalogID(forRow: row, in: state)

        guard
            let candidates = state.rails.candidates(
                forRow: row, ceiling: ceiling, formats: formats, limit: limit)
        else {
            // resolved, but no precomputed rail for this row - about half the
            // catalogue, the ordinary case until live compute exists
            return RecommendationSet(
                seed: seed, seedCatalogId: seedCatalogId, wTagEff: 0, used: 0, results: [])
        }

        let results = candidates.compactMap { present($0, in: state) }
        return RecommendationSet(
            seed: seed, seedCatalogId: seedCatalogId, wTagEff: 1, used: 1, results: results)
    }

    // MARK: resolution

    // tier 0 is exact and needs no text at all. tier 1 votes across the pool
    // rather than taking the first name that matched - the same discipline
    // v01's own resolve() follows, since Orihime's alias table also
    // preserves collisions rather than deduping them away
    private func resolve(_ payload: Payload, in state: Loaded) -> Seed {
        if let id = payload.catalogId,
            let row = state.rails.row(forCatalogId: Int64(id.rawValue))
        {
            return .linked(id, row: row)
        }
        let votes = state.aliasIndex.tally(for: payload.titles)
        if let best = votes.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) {
            let matched = payload.titles.first {
                state.aliasIndex.candidates(for: $0).contains(best.key)
            }
            return .resolved(row: best.key, matched: matched ?? "", votes: best.value)
        }
        return .projected(encoded: 0, dropped: payload.tags.count)
    }

    private func catalogID(forRow row: Int, in state: Loaded) -> CatalogID? {
        Int32(exactly: state.rails.catalogId(forRow: row)).map(CatalogID.init(rawValue:))
    }

    // MARK: presentation

    private func present(_ candidate: OrihimeCandidate, in state: Loaded) -> Recommendation? {
        guard let catalogId = Int32(exactly: candidate.catalogId).map(CatalogID.init(rawValue:))
        else { return nil }
        let row = candidate.row

        return Recommendation(
            catalogId: catalogId,
            row: row,
            title: state.display?.title(row) ?? "",
            authors: state.display?.authors(row) ?? [],
            artists: state.display?.artists(row) ?? [],
            cover: state.display?.cover(row),
            synopsis: state.display?.synopsis(row),
            tags: state.tagVocabulary.names(forRow: row),
            classification: state.rails.classification(forRow: row),
            publication: state.display?.status(row).publication ?? .Unknown,
            year: state.rails.year(forRow: row),
            format: state.rails.format(forRow: row) ?? .other,
            register: state.rails.register(forRow: row),
            score: candidate.score,
            // no per-block breakdown or confidence figure exists in the rails
            // table - only the final blend survives, see V02BlocksRequest.md.
            // the UI no longer renders either field, so a placeholder here
            // costs nothing
            confidence: 0,
            blocks: .init(tag: 0, embedding: 0, era: 0))
    }

    // MARK: loading

    private func state() throws -> Loaded {
        if let loaded { return loaded }
        if let failure { throw failure }
        do {
            let bundle = try OrihimeBundle.load(from: source)
            let state = Loaded(
                bundle: bundle,
                rails: try OrihimeRails(bundle: bundle),
                aliasIndex: try OrihimeAliasIndex(bundle: bundle),
                tagVocabulary: try OrihimeTagVocabulary(bundle: bundle),
                display: OrihimeDisplay(bundle: bundle))
            loaded = state
            return state
        } catch let error as RecommenderError {
            failure = error
            throw error
        } catch {
            let wrapped = RecommenderError.malformed(
                file: "bundle", reason: String(describing: error))
            failure = wrapped
            throw wrapped
        }
    }
}

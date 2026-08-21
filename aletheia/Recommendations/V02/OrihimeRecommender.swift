//
//  OrihimeRecommender.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import CoreGraphics
import Foundation
import ImageIO
import Tagged

// v02's adapter. same actor-per-load-once shape as V01Recommender - the only
// mutable state is whether the pack has loaded yet
//
// three answers, depending on what a seed resolves to: a precomputed rail
// (fast, the common case for a popular/library title), a real catalogue row
// with no rail (scored live from its own already-stored vectors, no
// encoding - liveScore()), or nothing found at all (scored live from an
// on-device text/cover encode - projected()). a missing scorer/relations
// table degrades any of the live paths to empty rather than guessing, the
// same "an addition to a screen, never load-bearing" discipline every
// recommender already follows
actor OrihimeRecommender: RecommenderService {
    private struct Loaded {
        let bundle: OrihimeBundle
        let rails: OrihimeRails
        let aliasIndex: OrihimeAliasIndex
        let tagVocabulary: OrihimeTagVocabulary
        let display: OrihimeDisplay?
        // nil when OrihimeScorer's own init failed (a malformed live-compute
        // file) - a resolved query never touches these, so that failure
        // degrades only the unresolved path rather than the whole recommender
        let scorer: OrihimeScorer?
        let relations: OrihimeRelations?
        let coverProjection: OrihimeCoverProjection?
        let textEncoder: OrihimeTextEncoder
        let coverEncoder: OrihimeCoverEncoder
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
            return await projected(payload, in: state, ceiling: ceiling, formats: formats, limit: limit)
        }
        let seedCatalogId = catalogID(forRow: row, in: state)

        guard
            let candidates = state.rails.candidates(
                forRow: row, ceiling: ceiling, formats: formats, limit: limit)
        else {
            // resolved, but no precomputed rail for this row - about half the
            // catalogue. its own vectors already live in the pack, so this
            // scores live without any on-device encoding, unlike an
            // unresolved seed
            return liveScore(row: row, seed: seed, seedCatalogId: seedCatalogId, in: state,
                ceiling: ceiling, formats: formats, limit: limit)
        }

        let results = candidates.compactMap { present($0, in: state) }
        return RecommendationSet(
            seed: seed, seedCatalogId: seedCatalogId, wTagEff: 1, used: 1, results: results)
    }

    // MARK: live compute

    // the unresolved path: nothing matched a row, so score directly against
    // what this pool actually has - title/synopsis/tags/year/cover - the
    // same full blend a resolved rail already answers, run live. "two modes,
    // not one degraded and one full", per V02Artifact.md
    private func projected(
        _ payload: Payload, in state: Loaded, ceiling: ContentCeiling, formats: Set<CatalogFormat>,
        limit: Int
    ) async -> RecommendationSet {
        let matchedColumns = state.tagVocabulary.columns(forNames: payload.tags)
        let seed = Seed.projected(
            encoded: matchedColumns.count, dropped: max(0, payload.tags.count - matchedColumns.count))

        // scorer unavailable is already logged once, at load time (state())
        // - repeating it per query would just be noise
        guard let scorer = state.scorer else {
            return RecommendationSet(seed: seed, seedCatalogId: nil, wTagEff: 0, used: 0, results: [])
        }

        var virtualSeed = OrihimeVirtualSeed()
        virtualSeed.title = payload.titles.first ?? ""
        virtualSeed.synopsis = payload.synopsis
        virtualSeed.tagNames = payload.tags
        virtualSeed.year = payload.year

        var synopsisEmbedding: [Float]?
        let trimmedSynopsis = payload.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSynopsis.isEmpty {
            do {
                try await state.textEncoder.prepare(bundle: state.bundle)
                let raw = try await state.textEncoder.encode(trimmedSynopsis)
                synopsisEmbedding = scorer.synopsisVector(fromRawEmbedding: raw)
            } catch {
                AppLog.shared.log(
                    "orihime live-compute text encode failed - \(error)",
                    level: .error, category: "orihime")
            }
        }

        var coverEmbedding: [Float]?
        if let coverURL = payload.cover, let coverProjection = state.coverProjection,
            let cgImage = Self.decodeCover(coverURL)
        {
            do {
                try await state.coverEncoder.prepare(bundle: state.bundle)
                let raw = try await state.coverEncoder.encode(cgImage)
                coverEmbedding = try coverProjection.project(raw)
            } catch {
                AppLog.shared.log(
                    "orihime live-compute cover encode failed - \(error)",
                    level: .error, category: "orihime")
            }
        }

        // no synopsis, no cover, no known tags at all - refuse rather than
        // rank on nothing, the same discipline v01's own divide-by-zero
        // guard already follows
        guard synopsisEmbedding != nil || coverEmbedding != nil || !matchedColumns.isEmpty else {
            AppLog.shared.log(
                "orihime live-compute refused (thin seed) - synopsis \(payload.synopsis.count) chars, cover \(payload.cover != nil ? "present" : "absent"), \(matchedColumns.count)/\(payload.tags.count) tags matched",
                category: "orihime")
            return RecommendationSet(seed: seed, seedCatalogId: nil, wTagEff: 0, used: 0, results: [])
        }

        let result = scorer.score(
            seed: virtualSeed, synopsisEmbedding: synopsisEmbedding, coverEmbedding: coverEmbedding,
            ceiling: ceiling, formats: formats, limit: limit)

        let candidates = result.scored.map {
            OrihimeCandidate(
                row: $0.row, catalogId: state.rails.catalogId(forRow: $0.row), score: Float($0.score))
        }
        let results = candidates.compactMap { present($0, in: state) }
        if result.scored.count != results.count {
            AppLog.shared.log(
                "orihime projected() - present() dropped \(result.scored.count - results.count) of \(result.scored.count) scored candidates",
                level: .error, category: "orihime")
        }

        AppLog.shared.log(
            "orihime live-compute - synopsis \(synopsisEmbedding != nil), cover \(coverEmbedding != nil), \(matchedColumns.count)/\(payload.tags.count) tags, used \(String(format: "%.2f", result.used)), \(results.count) results",
            category: "orihime")

        return RecommendationSet(
            seed: seed, seedCatalogId: nil, wTagEff: Float(result.tagGate), used: Float(result.used),
            results: results)
    }

    // resolved, but no precomputed rail: score this row live against the
    // catalogue using its own already-stored vectors - no encoding, cheaper
    // than an unresolved seed. relations/scorer missing degrades to empty
    // rather than guessing, same as everywhere else in this actor
    private func liveScore(
        row: Int, seed: Seed, seedCatalogId: CatalogID?, in state: Loaded,
        ceiling: ContentCeiling, formats: Set<CatalogFormat>, limit: Int
    ) -> RecommendationSet {
        guard let scorer = state.scorer, let relations = state.relations else {
            return RecommendationSet(
                seed: seed, seedCatalogId: seedCatalogId, wTagEff: 0, used: 0, results: [])
        }

        let result = scorer.score(
            seedRow: row, relatedRows: relations.rows(relatedTo: row),
            ceiling: ceiling, formats: formats, limit: limit)

        let candidates = result.scored.map {
            OrihimeCandidate(
                row: $0.row, catalogId: state.rails.catalogId(forRow: $0.row), score: Float($0.score))
        }
        let results = candidates.compactMap { present($0, in: state) }

        AppLog.shared.log(
            "orihime live-compute (resolved row \(row)) - used \(String(format: "%.2f", result.used)), \(results.count) results",
            category: "orihime")

        return RecommendationSet(
            seed: seed, seedCatalogId: seedCatalogId, wTagEff: Float(result.tagGate),
            used: Float(result.used), results: results)
    }

    private static func decodeCover(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
            let rails = try OrihimeRails(bundle: bundle)
            let tagVocabulary = try OrihimeTagVocabulary(bundle: bundle)

            var scorer: OrihimeScorer?
            do {
                scorer = try OrihimeScorer(bundle: bundle, rails: rails, tagVocabulary: tagVocabulary)
            } catch {
                AppLog.shared.log(
                    "orihime scorer unavailable, live compute disabled - \(error)",
                    level: .error, category: "orihime")
            }
            var coverProjection: OrihimeCoverProjection?
            do {
                coverProjection = try OrihimeCoverProjection(bundle: bundle)
            } catch {
                AppLog.shared.log(
                    "orihime cover projection unavailable - \(error)", level: .error, category: "orihime")
            }
            var relations: OrihimeRelations?
            do {
                relations = try OrihimeRelations(bundle: bundle)
            } catch {
                AppLog.shared.log(
                    "orihime relations unavailable - \(error)", level: .error, category: "orihime")
            }

            let state = Loaded(
                bundle: bundle,
                rails: rails,
                aliasIndex: try OrihimeAliasIndex(bundle: bundle),
                tagVocabulary: tagVocabulary,
                display: OrihimeDisplay(bundle: bundle),
                scorer: scorer,
                relations: relations,
                coverProjection: coverProjection,
                textEncoder: OrihimeTextEncoder(),
                coverEncoder: OrihimeCoverEncoder())
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

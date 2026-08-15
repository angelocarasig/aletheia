//
//  V01Recommender.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation
import Tagged

// the v01 content model. an actor because the only mutable state it has is
// whether it has loaded yet, which is exactly what an actor is for - the same
// shape as Compositor.Assets and CoverDownloader
//
// scoring itself is pure and runs off the main actor by construction. the hazard
// here is the inverse of the usual one: an extension inheriting @MainActor would
// put a 120M multiply-add scan on the main thread, which has already happened
// once in this codebase
actor V01Recommender: RecommenderService {
    private struct Loaded {
        let bundle: ModelBundle
        let scorer: Scorer
        let aliases: AliasIndex
        let vocabulary: TagVocabulary
        let metadata: CatalogMetadata?
        // ids are ascending in fit order, so a catalogue id resolves by binary
        // search rather than by a 302,894-entry dictionary. checked rather than
        // assumed - a future export that reorders rows would make this silently
        // wrong, and a wrong row is a wrong recommendation
        let idsAscending: Bool
    }

    private var loaded: Loaded?
    private var failure: RecommenderError?

    var descriptor: RecommenderDescriptor {
        get async {
            guard let state = try? state() else {
                return RecommenderDescriptor(slug: "v01", name: "Content v01",
                                             formatVersion: 0, titleCount: 0,
                                             encodesText: false, hasMetadata: false)
            }
            return RecommenderDescriptor(
                slug: "v01",
                name: "Content v01",
                formatVersion: state.bundle.manifest.formatVersion,
                titleCount: state.bundle.titleCount,
                encodesText: false,
                hasMetadata: state.metadata != nil)
        }
    }

    func warm() async {
        let started = Date()
        guard let state = try? state() else {
            AppLog.shared.log("model not available", category: "recommender")
            return
        }
        // state() already proved the bundle loads, decodes and size-checks, which
        // is the half of a health check worth having at launch. the other half -
        // that scoring answers - is what the DEBUG probe covers, and paying a
        // full throwaway query for it costs more launch time than the paging it
        // was meant to move
        let how = state.scorer.touchPages()
        AppLog.shared.log(
            String(format: "warmed in %.0fms - %@", Date().timeIntervalSince(started) * 1000, how),
            category: "recommender")
    }

    func recommend(_ payload: Payload,
                   ceiling: ContentCeiling,
                   formats: Set<CatalogFormat>,
                   limit: Int) async throws -> RecommendationSet {
        let state = try state()
        let types = Set(formats.map(\.rawValue))

        let seed = resolve(payload, in: state)
        let result: Scorer.Result
        switch seed {
        case .linked(_, let row), .resolved(let row, _, _):
            result = state.scorer.rank(row: row, ceiling: ceiling.rawValue,
                                       types: types, k: limit)
        case .projected:
            let vector = state.vocabulary.encode(payload.tags)
            // every block declined. scoring would divide by zero and rank noise,
            // so the honest answer is nothing rather than something
            guard !vector.columns.isEmpty else {
                return RecommendationSet(seed: seed, seedCatalogId: nil,
                                         wTagEff: 0, used: 0, results: [])
            }
            result = state.scorer.rank(vector: vector, ceiling: ceiling.rawValue,
                                       types: types, k: limit)
        }

        return RecommendationSet(
            seed: seed,
            seedCatalogId: seed.row.map { CatalogID(rawValue: state.scorer.catalogId(of: $0)) },
            wTagEff: result.applied.wTagEff,
            used: result.applied.used,
            results: result.ranked.map { present($0, in: state) })
    }

    // MARK: resolution

    // tier 0 is exact and needs no text at all. tier 1 votes across the pool
    // rather than taking the first name that matches, which is a shipped bug in
    // the reference implementation
    private func resolve(_ payload: Payload, in state: Loaded) -> Seed {
        if let id = payload.catalogId, let row = row(for: id, in: state) {
            return .linked(id, row: row)
        }
        let votes = state.aliases.tally(for: payload.titles)
        if let best = votes.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) {
            let matched = payload.titles.first {
                state.aliases.candidates(for: $0).contains(best.key)
            }
            return .resolved(row: best.key, matched: matched ?? "", votes: best.value)
        }
        let encoded = state.vocabulary.encode(payload.tags)
        return .projected(encoded: encoded.columns.count,
                          dropped: max(0, payload.tags.count - encoded.columns.count))
    }

    private func row(for id: CatalogID, in state: Loaded) -> Int? {
        let target = id.rawValue
        let n = state.bundle.titleCount
        guard state.idsAscending else {
            return (0..<n).first { state.scorer.catalogId(of: $0) == target }
        }
        var low = 0, high = n - 1
        while low <= high {
            let mid = (low + high) / 2
            let value = state.scorer.catalogId(of: mid)
            if value == target { return mid }
            if value < target { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    // MARK: presentation

    private func present(_ ranked: Scorer.Ranked, in state: Loaded) -> Recommendation {
        let row = ranked.row
        let titles = (try? state.bundle.array("titles.bin", "offsets", of: UInt32.self))
        let title = titles.flatMap { offsets -> String? in
            guard let blob = try? state.bundle.blob("titles.blob") else { return nil }
            let lo = Int(offsets[row]), hi = Int(offsets[row + 1])
            guard hi <= blob.count, hi >= lo else { return nil }
            return String(data: blob[lo..<hi], encoding: .utf8)
        } ?? ""

        return Recommendation(
            catalogId: CatalogID(rawValue: ranked.catalogId),
            row: row,
            title: title,
            authors: state.metadata?.authors(row) ?? [],
            artists: state.metadata?.artists(row) ?? [],
            cover: state.metadata?.cover(row),
            synopsis: state.metadata?.synopsis(row),
            tags: state.vocabulary.names(for: state.scorer.columns(of: row)),
            classification: ContentCeiling(rawValue: state.scorer.rating(of: row))?.classification ?? .Unknown,
            publication: state.metadata?.status(row).publication ?? .Unknown,
            year: state.scorer.publicationYear(of: row),
            format: CatalogFormat(rawValue: state.scorer.format(of: row)) ?? .other,
            register: RegisterAxis(rawValue: state.scorer.register(of: row)) ?? .general,
            score: ranked.score,
            confidence: ranked.confidence,
            blocks: .init(tag: ranked.tag, embedding: ranked.embedding, era: ranked.era))
    }

    // MARK: loading

    // lazy and held. mapping is nearly free so there is nothing to gain from
    // loading eagerly, and nothing to gain from ever letting it go
    private func state() throws -> Loaded {
        if let loaded { return loaded }
        if let failure { throw failure }
        do {
            let bundle = try ModelBundle.load()
            let scorer = try Scorer(bundle: bundle)
            let ids = try bundle.array("ids.bin", "catalogId", of: Int32.self)
            let ascending = ids.withUnsafeBufferPointer { values -> Bool in
                for i in 1..<values.count where values[i] < values[i - 1] { return false }
                return true
            }
            let state = Loaded(bundle: bundle,
                               scorer: scorer,
                               aliases: try AliasIndex(bundle: bundle),
                               vocabulary: try TagVocabulary(bundle: bundle),
                               metadata: CatalogMetadata(bundle: bundle),
                               idsAscending: ascending)
            loaded = state
            return state
        } catch let error as RecommenderError {
            failure = error
            throw error
        } catch {
            let wrapped = RecommenderError.malformed(file: "bundle",
                                                     reason: String(describing: error))
            failure = wrapped
            throw wrapped
        }
    }
}

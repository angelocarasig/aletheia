//
//  OrihimeScorer.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Accelerate
import Foundation

// the live-compute path: scores a virtual seed against every eligible
// candidate, exactly heuresis' own Blend.explain_virtual() (blend/blend.py) -
// candidate filter, per-block soft-fill, z-score over the candidate set,
// weighted blend, popularity prior. everything the resolved rail path skips
// by having the answer precomputed already
//
// format is not wired in - no source in this app reports a series' type, so
// there is nowhere to source seed.seriesType from yet (see
// OrihimeVirtualSeed). the block stays declared in params/blend.json and
// simply never gates on for a virtual seed until that data exists; title and
// appeal are the same story for a different reason, see blend.json's own
// virtual_seed.title_block note and V02Artifact.md
struct OrihimeScorer: Sendable {
    struct Scored: Sendable {
        let row: Int
        let score: Double
    }

    struct Result: Sendable {
        let scored: [Scored]
        // the tags block's own seed-side gate (0...1, how much tag evidence
        // there was) - v01's own wTagEff, carried over so a live-compute
        // result reports the same figure a projected v01 result always did
        let tagGate: Double
        // fraction of the blend's attempted weight that actually fired -
        // weightSum / the sum of every attempted block's weight, 0 when
        // nothing fired at all (thin_seed, refused before scoring)
        let used: Double
    }

    private static let synopsisDim = 384
    private static let coverDim = 128

    private let rails: OrihimeRails
    private let tagVocabulary: OrihimeTagVocabulary
    private let eraTrend: OrihimeEraTrend
    private let popularity: OrihimePopularity
    private let blend: OrihimeBlendSpec

    private let synopsisVectors: MappedArray<Int8>
    private let synopsisScale: Float
    private let synopsisGate: [Double]
    private let synopsisMean: [Float]

    private let coverVectors: MappedArray<Int8>
    private let coverScale: Float
    private let coverGate: [Double]

    private let eraGate: [Double]
    private let tagCandidateGate: [Double]

    private let titleCount: Int

    init(
        bundle: OrihimeBundle, rails: OrihimeRails, tagVocabulary: OrihimeTagVocabulary
    ) throws {
        self.rails = rails
        self.tagVocabulary = tagVocabulary
        eraTrend = try OrihimeEraTrend(bundle: bundle)
        popularity = try OrihimePopularity(bundle: bundle)
        blend = try OrihimeBlendSpec.load(bundle: bundle)

        titleCount = rails.titleCount

        synopsisVectors = try bundle.array("vectors/synopsis.npy", of: Int8.self)
        synopsisScale = try Self.scalar(bundle, "vectors/synopsis-scale.npy")
        let synopsisGateRaw = try bundle.array("vectors/synopsis_gate.npy", of: Float16.self)
        synopsisGate = synopsisGateRaw.withUnsafeBufferPointer { values in
            (0..<values.count).map { Double(values[$0]) }
        }
        let meanRaw = try bundle.array("params/text-synopsis-mean.npy", of: Float.self)
        synopsisMean = meanRaw.withUnsafeBufferPointer { Array($0) }

        let cover = try bundle.array("vectors/cover.npy", of: Int8.self)
        coverVectors = cover
        coverScale = try Self.scalar(bundle, "vectors/cover-scale.npy")
        coverGate = Self.coverGate(cover, titleCount: titleCount, dim: Self.coverDim)

        eraGate = Self.eraGate(rails, titleCount: titleCount)

        let tagFull = blend.block("tags")?.param("tag_count_full", 12) ?? 12
        tagCandidateGate = tagVocabulary.candidateGate(full: tagFull)
    }

    // free functions rather than inline closures on self's own properties -
    // a struct init's definite-initialization checker treats a closure
    // called through self (even a non-escaping one, even on an already-
    // assigned property) as needing every stored property initialized
    // first, which nothing else in this init can guarantee mid-way through
    private static func coverGate(_ vectors: MappedArray<Int8>, titleCount: Int, dim: Int) -> [Double]
    {
        var gate = [Double](repeating: 0, count: titleCount)
        vectors.withUnsafeBufferPointer { values in
            for row in 0..<titleCount {
                let base = row * dim
                for d in 0..<dim where values[base + d] != 0 {
                    gate[row] = 1
                    break
                }
            }
        }
        return gate
    }

    private static func eraGate(_ rails: OrihimeRails, titleCount: Int) -> [Double] {
        var gate = [Double](repeating: 0, count: titleCount)
        rails.withYears { years in
            for row in 0..<titleCount where years[row] != OrihimeRails.yearUnknownRaw {
                gate[row] = 1
            }
        }
        return gate
    }

    private static func scalar(_ bundle: OrihimeBundle, _ file: String) throws -> Float {
        let array = try bundle.array(file, of: Float.self)
        guard array.count == 1 else {
            throw RecommenderError.malformed(file: file, reason: "expected a single scale value")
        }
        return array[0]
    }

    // unit(embedding - mean) - the exact transform text.py's
    // SynopsisBlock.similarity_to_virtual() applies before scoring, done here
    // rather than by the caller since the mean is this scorer's own data
    func synopsisVector(fromRawEmbedding raw: [Float]) -> [Float] {
        var centred = [Float](repeating: 0, count: raw.count)
        vDSP_vsub(synopsisMean, 1, raw, 1, &centred, 1, vDSP_Length(raw.count))
        var norm: Float = 0
        vDSP_svesq(centred, 1, &norm, vDSP_Length(centred.count))
        norm = norm.squareRoot()
        guard norm > 0 else { return centred }
        var unit = [Float](repeating: 0, count: centred.count)
        var divisor = norm
        vDSP_vsdiv(centred, 1, &divisor, &unit, 1, vDSP_Length(centred.count))
        return unit
    }

    // synopsisEmbedding: this scorer's own synopsisVector(fromRawEmbedding:)
    // output. coverEmbedding: already unit-projected to 128-d via
    // OrihimeCoverProjection - the caller's job, that type already exists and
    // is verified independently, no need to duplicate it here
    func score(
        seed: OrihimeVirtualSeed,
        synopsisEmbedding: [Float]?,
        coverEmbedding: [Float]?,
        ceiling: ContentCeiling,
        formats: Set<CatalogFormat>,
        limit: Int
    ) -> Result {
        let candidateMask = rails.candidateMask(ceiling: ceiling, formats: formats, register: seed.register)
        let candidateRows = (0..<titleCount).filter { candidateMask[$0] }
        guard !candidateRows.isEmpty else {
            AppLog.shared.log(
                "orihime scorer.score() - 0 candidate rows (ceiling \(ceiling), register \(seed.register))",
                level: .error, category: "orihime")
            return Result(scored: [], tagGate: 0, used: 0)
        }

        var total = [Double](repeating: 0, count: titleCount)
        var weightSum = 0.0
        var tagGate = 0.0
        // the sum of every block this scorer can attempt for a virtual seed
        // (title/appeal/format excluded - permanently unavailable here, see
        // this type's own header) - the denominator for "used"
        let totalWeight =
            ["tags", "synopsis", "era", "cover"].reduce(0.0) { $0 + (blend.block($1)?.weight ?? 0) }

        func contribute(similarity: [Double], candidateGate: [Double], seedGate: Double, weight: Double) {
            guard seedGate > 0, weight > 0 else { return }
            let filled = softFill(similarity, gate: candidateGate)
            let z = zScore(filled, over: candidateRows)
            let effective = seedGate * weight
            for row in 0..<titleCount { total[row] += effective * z[row] }
            weightSum += effective
        }

        // tags - every given name at equal weight, gate ~ how many matched
        if let spec = blend.block("tags") {
            let full = spec.param("tag_count_full", 12)
            let columns = tagVocabulary.columns(forNames: seed.tagNames)
            let gate = tagVocabulary.gate(tagCount: columns.count, full: full)
            tagGate = gate
            if gate > 0 {
                let similarity = tagVocabulary.similarity(toColumns: columns)
                contribute(
                    similarity: similarity, candidateGate: tagCandidateGate, seedGate: gate,
                    weight: spec.weight)
            }
        }

        // synopsis - gate ~ how much text there is, zero_chars..full_chars
        if let spec = blend.block("synopsis"), let synopsisEmbedding {
            let zeroChars = spec.param("zero_chars", 30)
            let fullChars = spec.param("full_chars", 240)
            let chars = seed.synopsis.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").count
            let gate = min(
                max((Double(chars) - zeroChars) / max(fullChars - zeroChars, 1e-9), 0), 1)
            if gate > 0 {
                let similarity = denseSimilarity(
                    seed: synopsisEmbedding, vectors: synopsisVectors, scale: synopsisScale,
                    dim: Self.synopsisDim)
                contribute(
                    similarity: similarity, candidateGate: synopsisGate, seedGate: gate,
                    weight: spec.weight)
            }
        }

        // era - gate ~ whether the seed's year is known; gain rewards a wave-
        // bound tag set (villainess, isekai) mattering more for era than a
        // seed whose tags aren't wave-bound at all
        if let spec = blend.block("era"), let seedYear = seed.year {
            let tau = spec.param("year_tau", 3.0)
            let waveGain = spec.param("wave_gain", 1.0)
            let topTags = Int(spec.param("trend_top_tags", 2))
            let trend = eraTrend.trend(forTagNames: seed.tagNames, top: topTags)
            let gain = 1.0 + waveGain * trend
            let similarity = eraSimilarity(seedYear: seedYear, tau: tau)
            contribute(
                similarity: similarity, candidateGate: eraGate, seedGate: 1.0,
                weight: spec.weight * gain)
        }

        // cover - gate ~ whether the seed has a cover vector at all (binary)
        if let spec = blend.block("cover"), let coverEmbedding {
            let similarity = denseSimilarity(
                seed: coverEmbedding, vectors: coverVectors, scale: coverScale, dim: Self.coverDim)
            contribute(
                similarity: similarity, candidateGate: coverGate, seedGate: 1.0, weight: spec.weight)
        }

        if weightSum > 0 {
            for row in 0..<titleCount { total[row] /= weightSum }
        }

        let popularityZ = zScore(popularity.percentile, over: candidateRows)
        for row in 0..<titleCount { total[row] += blend.popularityWeight * popularityZ[row] }

        let ranked = candidateRows.sorted { total[$0] > total[$1] }
        let scored = ranked.prefix(limit).map { Scored(row: $0, score: total[$0]) }
        let used = totalWeight > 0 ? weightSum / totalWeight : 0
        return Result(scored: Array(scored), tagGate: tagGate, used: used)
    }

    // the resolved-but-no-rail path: a real catalogue row with no precomputed
    // answer, roughly half the catalogue. cheaper than the virtual-seed
    // score() above - every block's seed-side evidence already lives in the
    // pack (its own tag row, its own synopsis/cover vector, its own year), so
    // there is nothing to encode. Blend.score(seed_row) (blend.py), not
    // explain_virtual()
    func score(
        seedRow: Int,
        relatedRows: [Int],
        ceiling: ContentCeiling,
        formats: Set<CatalogFormat>,
        limit: Int
    ) -> Result {
        let candidateMask = rails.candidateMask(
            forSeedRow: seedRow, ceiling: ceiling, formats: formats, relatedRows: relatedRows)
        let candidateRows = (0..<titleCount).filter { candidateMask[$0] }
        guard !candidateRows.isEmpty else { return Result(scored: [], tagGate: 0, used: 0) }

        var total = [Double](repeating: 0, count: titleCount)
        var weightSum = 0.0
        var tagGate = 0.0
        let totalWeight =
            ["tags", "synopsis", "era", "cover"].reduce(0.0) { $0 + (blend.block($1)?.weight ?? 0) }

        func contribute(similarity: [Double], candidateGate: [Double], seedGate: Double, weight: Double) {
            guard seedGate > 0, weight > 0 else { return }
            let filled = softFill(similarity, gate: candidateGate)
            let z = zScore(filled, over: candidateRows)
            let effective = seedGate * weight
            for row in 0..<titleCount { total[row] += effective * z[row] }
            weightSum += effective
        }

        if let spec = blend.block("tags") {
            let full = spec.param("tag_count_full", 12)
            let gate = tagVocabulary.gate(tagCount: tagVocabulary.tagCount(forRow: seedRow), full: full)
            tagGate = gate
            if gate > 0 {
                let similarity = tagVocabulary.similarity(toRow: seedRow)
                contribute(
                    similarity: similarity, candidateGate: tagCandidateGate, seedGate: gate,
                    weight: spec.weight)
            }
        }

        if let spec = blend.block("synopsis") {
            let gate = synopsisGate[seedRow]
            if gate > 0 {
                let seedVector = dequantizedRow(
                    synopsisVectors, row: seedRow, scale: synopsisScale, dim: Self.synopsisDim)
                let similarity = denseSimilarity(
                    seed: seedVector, vectors: synopsisVectors, scale: synopsisScale,
                    dim: Self.synopsisDim)
                contribute(
                    similarity: similarity, candidateGate: synopsisGate, seedGate: gate,
                    weight: spec.weight)
            }
        }

        if let spec = blend.block("era"), let seedYear = rails.year(forRow: seedRow) {
            let tau = spec.param("year_tau", 3.0)
            let waveGain = spec.param("wave_gain", 1.0)
            let topTags = Int(spec.param("trend_top_tags", 2))
            let trend = eraTrend.trend(forTagNames: tagVocabulary.names(forRow: seedRow), top: topTags)
            let gain = 1.0 + waveGain * trend
            let similarity = eraSimilarity(seedYear: seedYear, tau: tau)
            contribute(
                similarity: similarity, candidateGate: eraGate, seedGate: 1.0,
                weight: spec.weight * gain)
        }

        if let spec = blend.block("cover") {
            let gate = coverGate[seedRow]
            if gate > 0 {
                let seedVector = dequantizedRow(
                    coverVectors, row: seedRow, scale: coverScale, dim: Self.coverDim)
                let similarity = denseSimilarity(
                    seed: seedVector, vectors: coverVectors, scale: coverScale, dim: Self.coverDim)
                contribute(
                    similarity: similarity, candidateGate: coverGate, seedGate: gate,
                    weight: spec.weight)
            }
        }

        if weightSum > 0 {
            for row in 0..<titleCount { total[row] /= weightSum }
        }

        let popularityZ = zScore(popularity.percentile, over: candidateRows)
        for row in 0..<titleCount { total[row] += blend.popularityWeight * popularityZ[row] }

        let ranked = candidateRows.sorted { total[$0] > total[$1] }
        let scored = ranked.prefix(limit).map { Scored(row: $0, score: total[$0]) }
        let used = totalWeight > 0 ? weightSum / totalWeight : 0
        return Result(scored: Array(scored), tagGate: tagGate, used: used)
    }

    // dim raw values from a packed row, dequantised - the seed side of a
    // resolved-row dense similarity, sourced from the pack's own vectors
    // rather than an on-device encode
    private func dequantizedRow(
        _ vectors: MappedArray<Int8>, row: Int, scale: Float, dim: Int
    ) -> [Float] {
        var result = [Float](repeating: 0, count: dim)
        vectors.withUnsafeBufferPointer { values in
            let base = row * dim
            for d in 0..<dim { result[d] = Float(values[base + d]) * scale }
        }
        return result
    }

    // blends each row's raw similarity with the block-wide mean by how much
    // evidence that row has - a row with none neither wins nor loses on a
    // block it gives no signal for. base.py's Block.soft_fill()
    private func softFill(_ similarity: [Double], gate: [Double]) -> [Double] {
        var sum = 0.0
        var count = 0
        for i in 0..<similarity.count where gate[i] > 0 {
            sum += similarity[i]
            count += 1
        }
        let mean = count > 0 ? sum / Double(count) : 0

        var result = [Double](repeating: 0, count: similarity.count)
        for i in 0..<similarity.count {
            result[i] = gate[i] * similarity[i] + (1 - gate[i]) * mean
        }
        return result
    }

    // standardises against the mean/spread of the candidate rows only, then
    // applies that scale to every row - blend.py's z_scores(values, over=)
    private func zScore(_ values: [Double], over rows: [Int]) -> [Double] {
        var sum = 0.0
        for row in rows { sum += values[row] }
        let mean = sum / Double(rows.count)

        var sumSquares = 0.0
        for row in rows {
            let delta = values[row] - mean
            sumSquares += delta * delta
        }
        let spread = (sumSquares / Double(rows.count)).squareRoot()
        guard spread > 0 else { return [Double](repeating: 0, count: values.count) }

        return values.map { ($0 - mean) / spread }
    }

    // exp(-|years apart| / tau) for every row, including rows with an
    // unknown year - their similarity is meaningless but harmless, since
    // soft_fill discards it wherever the candidate gate is 0 anyway
    private func eraSimilarity(seedYear: Int, tau: Double) -> [Double] {
        var result = [Double](repeating: 0, count: titleCount)
        rails.withYears { years in
            for row in 0..<titleCount {
                let diff = abs(Double(years[row]) - Double(seedYear))
                result[row] = exp(-diff / tau)
            }
        }
        return result
    }

    // dot(seed, dequantised row) for every row - the pack's own compute_units
    // names this step "Accelerate (not Core ML)", the one place vDSP is worth
    // reaching for over a plain Swift loop: ~302K rows x (384 or 128) dims
    private func denseSimilarity(
        seed: [Float], vectors: MappedArray<Int8>, scale: Float, dim: Int
    ) -> [Double] {
        var result = [Double](repeating: 0, count: titleCount)
        var floatRow = [Float](repeating: 0, count: dim)

        vectors.withUnsafeBufferPointer { values in
            seed.withUnsafeBufferPointer { seedPointer in
                floatRow.withUnsafeMutableBufferPointer { rowPointer in
                    guard let base = values.baseAddress, let seedBase = seedPointer.baseAddress,
                        let rowBase = rowPointer.baseAddress
                    else { return }
                    for row in 0..<titleCount {
                        vDSP_vflt8(base + row * dim, 1, rowBase, 1, vDSP_Length(dim))
                        var dot: Float = 0
                        vDSP_dotpr(rowBase, 1, seedBase, 1, &dot, vDSP_Length(dim))
                        result[row] = Double(dot * scale)
                    }
                }
            }
        }
        return result
    }
}

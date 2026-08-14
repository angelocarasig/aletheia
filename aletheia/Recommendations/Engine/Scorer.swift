//
//  Scorer.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// the ranking arithmetic, and nothing else. three blocks scored independently
// across the whole catalogue, each standardised, then blended and filtered
//
// z-scoring before the blend is not a refinement: the blocks have very different
// natural spreads, and blended raw whichever is widest dominates regardless of
// its weight
struct Scorer: Sendable {
    struct Ranked: Sendable {
        let row: Int
        let catalogId: Int32
        let score: Float
        let confidence: Float
        let tag: Float
        let embedding: Float
        let era: Float
    }

    struct Applied: Sendable {
        let wTagEff: Float
        let used: Float
        let embeddingRan: Bool
        let eraRan: Bool
    }

    struct Result: Sendable {
        let applied: Applied
        let ranked: [Ranked]
    }

    private let bundle: ModelBundle
    private let indptr: MappedArray<UInt32>
    private let indices: MappedArray<UInt16>
    private let values: MappedArray<UInt8>
    private let embeddings: MappedArray<Int8>
    private let hasEmbed: MappedArray<UInt8>
    private let year: MappedArray<Int16>
    private let flags: MappedArray<UInt8>
    private let ids: MappedArray<Int32>

    private let n: Int
    private let vocab: Int
    private let dims: Int
    private let tagScale: Float
    private let embedScale: Float
    private let constants: ModelManifest.Constants
    private let yearUnknown: Int16

    init(bundle: ModelBundle) throws {
        self.bundle = bundle
        indptr = try bundle.array("tags.bin", "indptr", of: UInt32.self)
        indices = try bundle.array("tags.bin", "indices", of: UInt16.self)
        values = try bundle.array("tags.bin", "values", of: UInt8.self)
        embeddings = try bundle.array("embeddings.bin", "values", of: Int8.self)
        hasEmbed = try bundle.array("has_embed.bin", "hasEmbedding", of: UInt8.self)
        year = try bundle.array("meta.bin", "year", of: Int16.self)
        flags = try bundle.array("meta.bin", "flags", of: UInt8.self)
        ids = try bundle.array("ids.bin", "catalogId", of: Int32.self)

        n = bundle.manifest.titleCount
        vocab = bundle.manifest.tagVocabSize
        constants = bundle.manifest.constants
        yearUnknown = Int16(bundle.manifest.yearUnknown)

        guard let tags = bundle.manifest.files["tags.bin"],
              let embed = bundle.manifest.files["embeddings.bin"],
              let scale = tags.valueScale, let embedded = embed.valueScale,
              let dims = embed.dims
        else {
            throw RecommenderError.malformed(file: "manifest.json",
                                             reason: "missing a value scale or dims")
        }
        tagScale = Float(scale)
        embedScale = Float(embedded)
        self.dims = dims
    }

    func rank(row seed: Int, ceiling: Int, types: Set<Int>, k: Int) -> Result {
        // the raw blocks are what confidence and any debug readout report, and
        // the standardised copies are what the blend consumes. computed once and
        // copied - recomputing them would double a 120M multiply-add query
        var rawTag = [Float](repeating: 0, count: n)
        var rawEmb = [Float](repeating: 0, count: n)
        var era = [Float](repeating: 0, count: n)

        tagBlock(seed: seed, into: &rawTag)
        var tag = rawTag
        var emb = rawEmb

        // the taper. a seed with three tags matches thousands of titles at ~0.9,
        // so its tag block is trusted in proportion to the evidence behind it -
        // and 53% of the catalogue sits below the saturation point, which makes
        // this the common path rather than an edge case
        let nnz = Float(indptr[seed + 1] - indptr[seed])
        let wTagEff = constants.wTag * min(nnz / constants.tagSaturate, 1)

        let embeddingRan = hasEmbed[seed] == 1
        if embeddingRan {
            embeddingBlock(seed: seed, into: &rawEmb)
            emb = rawEmb
        }

        let eraRan = year[seed] != yearUnknown
        if eraRan { eraBlock(seed: seed, into: &era) }

        standardise(&tag)
        var score = tag
        for i in 0..<n { score[i] *= wTagEff }
        var used = wTagEff

        if embeddingRan {
            standardise(&emb)
            for i in 0..<n { score[i] += constants.wEmbed * emb[i] }
            used += constants.wEmbed
        }
        if eraRan {
            standardise(&era)
            for i in 0..<n { score[i] += constants.wYear * era[i] }
            used += constants.wYear
        }
        if used > 0 {
            for i in 0..<n { score[i] /= used }
        }

        let ranked = select(score: score, seed: seed, ceiling: ceiling, types: types, k: k,
                            wTagEff: wTagEff, rawTag: rawTag, rawEmb: rawEmb, era: era)

        return Result(applied: Applied(wTagEff: wTagEff, used: used,
                                       embeddingRan: embeddingRan, eraRan: eraRan),
                      ranked: ranked)
    }

    // the projected path: a payload that resolved to no catalogue row is scored
    // on its own encoded tags. there is no embedding block (the text encoder was
    // not exported) and no era block (this app stores no year), so used ==
    // wTagEff and one block of three carries the whole answer
    func rank(vector: TagVocabulary.Sparse, ceiling: Int, types: Set<Int>, k: Int) -> Result {
        var rawTag = [Float](repeating: 0, count: n)
        tagBlock(vector: vector, into: &rawTag)

        let wTagEff = constants.wTag * min(Float(vector.columns.count) / constants.tagSaturate, 1)
        var score = rawTag
        standardise(&score)
        // no seed row to exclude, and no register to match: a payload has neither,
        // so the guard is the caller's to apply if it knows better
        let ranked = select(score: score, seed: -1, ceiling: ceiling, types: types, k: k,
                            wTagEff: wTagEff, rawTag: rawTag,
                            rawEmb: [Float](repeating: 0, count: n),
                            era: [Float](repeating: 0, count: n))
        return Result(applied: Applied(wTagEff: wTagEff, used: wTagEff,
                                       embeddingRan: false, eraRan: false),
                      ranked: ranked)
    }

    // a row's tag columns, for turning a result back into names
    func columns(of row: Int) -> [Int] {
        indptr.withUnsafeBufferPointer { ptr in
            indices.withUnsafeBufferPointer { idx in
                (Int(ptr[row])..<Int(ptr[row + 1])).map { Int(idx[$0]) }
            }
        }
    }

    func register(of row: Int) -> Int { Int((flags[row] >> 5) & 0b11) }
    func format(of row: Int) -> Int { Int(flags[row] & 0b111) }
    func rating(of row: Int) -> Int { Int((flags[row] >> 3) & 0b11) }
    func publicationYear(of row: Int) -> Int? {
        let value = year[row]
        return value == yearUnknown ? nil : Int(value)
    }
    func catalogId(of row: Int) -> Int32 { ids[row] }

    // page the two big matrices in, without doing any of the work a query does.
    // the cost being moved is I/O - the first query faults in 116 MB of
    // embeddings - so touching one byte per page buys the whole benefit, where
    // running a real query would additionally z-score and sort 302,894 rows that
    // the real query is about to redo anyway
    //
    // the return value exists to stop the compiler eliminating loads it can prove
    // nothing reads
    @discardableResult
    func touchPages() -> Int {
        var sum = 0
        let stride = 4096
        embeddings.withUnsafeBufferPointer { buffer in
            var i = 0
            while i < buffer.count {
                sum &+= Int(buffer[i])
                i += stride
            }
        }
        values.withUnsafeBufferPointer { buffer in
            var i = 0
            while i < buffer.count {
                sum &+= Int(buffer[i])
                i += stride
            }
        }
        return sum
    }

    // MARK: blocks

    // both operands are quantised bytes, so the dot product is exact in Int32 and
    // the scale is applied once at the end. a row's nnz tops out at 444, so the
    // largest accumulator any row can reach is 444 * 255 * 255, which is nowhere
    // near overflow
    private func tagBlock(seed: Int, into out: inout [Float]) {
        var dense = [Int32](repeating: 0, count: vocab)
        indices.withUnsafeBufferPointer { idx in
            values.withUnsafeBufferPointer { val in
                indptr.withUnsafeBufferPointer { ptr in
                    for i in Int(ptr[seed])..<Int(ptr[seed + 1]) {
                        dense[Int(idx[i])] = Int32(val[i])
                    }
                    let squared = tagScale * tagScale
                    dense.withUnsafeBufferPointer { seedRow in
                        out.withUnsafeMutableBufferPointer { result in
                            for row in 0..<n {
                                var acc: Int32 = 0
                                for i in Int(ptr[row])..<Int(ptr[row + 1]) {
                                    acc += seedRow[Int(idx[i])] * Int32(val[i])
                                }
                                result[row] = Float(acc) * squared
                            }
                        }
                    }
                }
            }
        }
    }

    // rows with no synopsis hold a zero vector, and a zero dot product would read
    // as actively dissimilar. they take the block mean instead - a missing
    // synopsis is an absence, not a penalty
    // the same gather, but the seed side arrives as floats rather than bytes, so
    // the accumulator cannot be integer here
    private func tagBlock(vector: TagVocabulary.Sparse, into out: inout [Float]) {
        var dense = [Float](repeating: 0, count: vocab)
        for (i, column) in vector.columns.enumerated() where column < vocab {
            dense[column] = vector.values[i]
        }
        indices.withUnsafeBufferPointer { idx in
            values.withUnsafeBufferPointer { val in
                indptr.withUnsafeBufferPointer { ptr in
                    dense.withUnsafeBufferPointer { seedRow in
                        out.withUnsafeMutableBufferPointer { result in
                            for row in 0..<n {
                                var acc: Float = 0
                                for i in Int(ptr[row])..<Int(ptr[row + 1]) {
                                    acc += seedRow[Int(idx[i])] * Float(val[i])
                                }
                                result[row] = acc * tagScale
                            }
                        }
                    }
                }
            }
        }
    }

    // 116M int8 multiply-adds and the dominant cost of a query - 43ms of 57ms
    // when it ran on one core. that is 2.7 GB/s, a few percent of what the memory
    // system can do, so it is instruction-bound rather than bandwidth-bound
    //
    // rows are independent, so the work splits cleanly: each chunk writes a
    // disjoint slice of the output and keeps its own running sum, and the means
    // are combined afterwards. no locks, no shared accumulator
    //
    // a SIMD16 rewrite of the inner loop took this to 8ms and was reverted - it
    // passed everything in the simulator including all 200 golden rankings, and
    // crashed on arm64 hardware. it is NOT an alignment fault: loadUnaligned emits
    // align 1, arm64 does not fault on misaligned vector loads, and an alignment
    // bug would have crashed the simulator instead. cause unestablished, see
    // docs/platform/metal.md section 9
    //
    // a Metal kernel was then researched and NOT built: this parallel version got
    // most of the same win with none of the risk, and there is no batch path to
    // justify the rest. do not reach for either without reading port-plan.md 5.10
    private func embeddingBlock(seed: Int, into out: inout [Float]) {
        let dims = self.dims
        let rows = n
        let squared = embedScale * embedScale
        let base = seed * dims

        // enough chunks that a slow core cannot leave everyone waiting, but large
        // enough that dispatch overhead stays irrelevant against ~380 rows of work
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let chunks = max(1, min(cores * 4, (rows + 4095) / 4096))
        let span = (rows + chunks - 1) / chunks

        var sums = [Double](repeating: 0, count: chunks)
        var counts = [Int](repeating: 0, count: chunks)

        embeddings.withUnsafeBufferPointer { matrix in
            hasEmbed.withUnsafeBufferPointer { known in
                out.withUnsafeMutableBufferPointer { result in
                    sums.withUnsafeMutableBufferPointer { sums in
                        counts.withUnsafeMutableBufferPointer { counts in
                            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                                let low = chunk * span
                                let high = min(low + span, rows)
                                guard low < high else { return }

                                var total: Double = 0
                                var counted = 0
                                for row in low..<high {
                                    guard known[row] == 1 else { continue }
                                    var acc: Int32 = 0
                                    let start = row * dims
                                    for d in 0..<dims {
                                        acc += Int32(matrix[base + d]) * Int32(matrix[start + d])
                                    }
                                    let value = Float(acc) * squared
                                    result[row] = value
                                    total += Double(value)
                                    counted += 1
                                }
                                sums[chunk] = total
                                counts[chunk] = counted
                            }
                        }
                    }
                }
            }
        }

        // rows with no synopsis hold a zero vector, and a zero dot product would
        // read as actively dissimilar. they take the block mean instead - a
        // missing synopsis is an absence, not a penalty
        let counted = counts.reduce(0, +)
        guard counted > 0 else { return }
        let mean = Float(sums.reduce(0, +) / Double(counted))
        hasEmbed.withUnsafeBufferPointer { known in
            out.withUnsafeMutableBufferPointer { result in
                for row in 0..<rows where known[row] == 0 { result[row] = mean }
            }
        }
    }

    private func eraBlock(seed: Int, into out: inout [Float]) {
        year.withUnsafeBufferPointer { years in
            let anchor = Float(years[seed])
            var total: Double = 0
            var counted = 0
            out.withUnsafeMutableBufferPointer { result in
                for row in 0..<n {
                    guard years[row] != yearUnknown else { continue }
                    let value = expf(-abs(Float(years[row]) - anchor) / constants.yearTau)
                    result[row] = value
                    total += Double(value)
                    counted += 1
                }
                let mean = counted > 0 ? Float(total / Double(counted)) : 0
                for row in 0..<n where years[row] == yearUnknown { result[row] = mean }
            }
        }
    }

    // over the entire array, before any filtering. accumulated in Double because
    // a float32 sum over 302,894 terms loses enough precision to move a score
    // past the tolerance the fixtures are asserted at
    private func standardise(_ values: inout [Float]) {
        var total: Double = 0
        for v in values { total += Double(v) }
        let mean = total / Double(values.count)
        var variance: Double = 0
        for v in values {
            let d = Double(v) - mean
            variance += d * d
        }
        let sd = (variance / Double(values.count)).squareRoot()
        guard sd > 0 else {
            for i in values.indices { values[i] = 0 }
            return
        }
        let m = Float(mean), s = Float(sd)
        for i in values.indices { values[i] = (values[i] - m) / s }
    }

    // MARK: selection

    // ties are common enough that ordering them by whatever the sort does would
    // break parity: in a 200-seed sample 42 had an exact tie inside their top 20
    // and one had eight. so the order is total - score descending, then catalogue
    // id ascending - and the whole tie group is pulled in before it is applied
    private func select(score: [Float], seed: Int, ceiling: Int, types: Set<Int>, k: Int,
                        wTagEff: Float, rawTag: [Float], rawEmb: [Float], era: [Float]) -> [Ranked] {
        // a projected query passes seed -1: there is no row to exclude and no
        // register to hold the results to, because a payload has neither
        let seedRegister: UInt8? = seed >= 0 ? (flags[seed] >> 5) & 0b11 : nil
        var eligible = [Int]()
        eligible.reserveCapacity(n / 4)

        flags.withUnsafeBufferPointer { f in
            for row in 0..<n {
                guard row != seed else { continue }
                let bits = f[row]
                guard (bits >> 7) & 1 == 0 else { continue }
                guard Int((bits >> 3) & 0b11) <= ceiling else { continue }
                guard types.contains(Int(bits & 0b111)) else { continue }
                if let seedRegister, (bits >> 5) & 0b11 != seedRegister { continue }
                eligible.append(row)
            }
        }
        guard !eligible.isEmpty else { return [] }

        // kth largest first, so the sort only ever touches the tie group rather
        // than the whole eligible set
        let want = min(k, eligible.count)
        var top = eligible.map { score[$0] }
        top.sort(by: >)
        let cutoff = top[want - 1]

        let group = eligible.filter { score[$0] >= cutoff }
        let ordered = group.sorted { a, b in
            score[a] == score[b] ? ids[a] < ids[b] : score[a] > score[b]
        }

        let denominator = wTagEff + constants.wEmbed
        return ordered.prefix(want).map { row in
            // the era block is deliberately absent here. including it made a
            // title that merely shared the seed's publication year read as a 46%
            // content match
            let confidence = denominator > 0
                ? (wTagEff * max(rawTag[row], 0) + constants.wEmbed * max(rawEmb[row], 0)) / denominator
                : 0
            return Ranked(row: row, catalogId: ids[row], score: score[row],
                          confidence: confidence, tag: rawTag[row],
                          embedding: rawEmb[row], era: era[row])
        }
    }
}

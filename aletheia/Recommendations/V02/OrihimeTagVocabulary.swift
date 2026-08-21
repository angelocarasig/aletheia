//
//  OrihimeTagVocabulary.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// flat, id-equals-array-index vocabulary (confirmed against the real
// vocabulary.json - every entry's id matches its position), unlike v01's
// tagvocab.json which needs a name -> index dictionary. no ancestor-hierarchy
// decay here either - Orihime's tag block is flat weighted overlap, so there's
// no equivalent machinery to port
struct OrihimeTagVocabulary: Sendable {
    private struct Entry: Decodable {
        let id: Int
        let name: String
    }

    private let names: [String]
    // lowercased name -> vocabulary column, for a virtual seed's free-text tag
    // names - exact-name matching only, no fuzzy fallback, same discipline
    // heuresis' own tags.py similarity_to_virtual() uses (a plain .lower(),
    // not full NFKD - matching the reference implementation, not the docs)
    private let columnOfName: [String: Int]
    private let rowOffsets: MappedArray<Int64>
    private let tagIds: MappedArray<Int32>
    // raw per-tag weight (defining/core/recurrent/...), NOT L2-normalised -
    // tag_weights.npy ships the same pre-normalisation table TagsBlock.build()
    // starts from, so normalising is this type's job, done once at init
    private let tagWeights: MappedArray<Float16>
    // one L2 norm per row, precomputed once - every query needs it, no query
    // computes it twice
    private let rowNorms: [Float]
    // tag count per row, precomputed alongside the norms in the same pass -
    // the candidate-side gate a live-compute score() needs for every row,
    // not just the seed's own
    private let tagCounts: [Int]
    let titleCount: Int

    init(bundle: OrihimeBundle) throws {
        let data = try bundle.blob("vectors/tags/vocabulary.json")
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        var table = [String](repeating: "", count: entries.count)
        var byName: [String: Int] = [:]
        byName.reserveCapacity(entries.count)
        for entry in entries where entry.id < table.count {
            table[entry.id] = entry.name
            byName[entry.name.lowercased()] = entry.id
        }
        names = table
        columnOfName = byName
        rowOffsets = try bundle.array("vectors/tags/row_offsets.npy", of: Int64.self)
        tagIds = try bundle.array("vectors/tags/tag_ids.npy", of: Int32.self)
        tagWeights = try bundle.array("vectors/tags/tag_weights.npy", of: Float16.self)
        titleCount = rowOffsets.count - 1

        let (norms, counts) = Self.rowNormsAndCounts(
            offsets: rowOffsets, weights: tagWeights, titleCount: titleCount)
        rowNorms = norms
        tagCounts = counts
    }

    // a free function rather than a closure over self's own just-assigned
    // properties - a struct init's definite-initialization checker treats
    // that as needing every stored property set first, which this can't
    // guarantee mid-init
    private static func rowNormsAndCounts(
        offsets: MappedArray<Int64>, weights: MappedArray<Float16>, titleCount: Int
    ) -> ([Float], [Int]) {
        var norms = [Float](repeating: 0, count: titleCount)
        var counts = [Int](repeating: 0, count: titleCount)
        offsets.withUnsafeBufferPointer { offsets in
            weights.withUnsafeBufferPointer { weights in
                for row in 0..<titleCount {
                    var sumSquares: Float = 0
                    let lo = Int(offsets[row])
                    let hi = Int(offsets[row + 1])
                    for i in lo..<hi {
                        let w = Float(weights[i])
                        sumSquares += w * w
                    }
                    norms[row] = sumSquares.squareRoot()
                    counts[row] = hi - lo
                }
            }
        }
        return (norms, counts)
    }

    func names(forRow row: Int) -> [String] {
        rowOffsets.withUnsafeBufferPointer { offsets in
            guard row + 1 < offsets.count else { return [] }
            let lo = Int(offsets[row])
            let hi = Int(offsets[row + 1])
            guard hi > lo else { return [] }
            return tagIds.withUnsafeBufferPointer { ids in
                (lo..<hi).compactMap { i -> String? in
                    let id = Int(ids[i])
                    guard id < names.count else { return nil }
                    return names[id]
                }
            }
        }
    }

    // min(tag_count / tag_count_full, 1) - the same gate formula tags.py
    // uses for both a candidate row and a virtual seed, just evaluated
    // against whichever count is at hand
    func gate(tagCount: Int, full: Double) -> Double {
        guard full > 0 else { return 0 }
        return min(Double(tagCount) / full, 1.0)
    }

    func tagCount(forRow row: Int) -> Int {
        tagCounts[row]
    }

    // the tags block's per-candidate gate, for every row at once - what
    // score()'s soft-fill pass needs, computed from the counts already
    // cached at init rather than re-derived per query
    func candidateGate(full: Double) -> [Double] {
        tagCounts.map { gate(tagCount: $0, full: full) }
    }

    // vocabulary columns matching the seed's given names, unknown ones
    // dropped silently - exactly tags.py's similarity_to_virtual()
    func columns(forNames seedNames: [String]) -> [Int] {
        var seen = Set<Int>()
        var columns: [Int] = []
        for name in seedNames {
            guard let column = columnOfName[name.lowercased()], !seen.contains(column) else {
                continue
            }
            seen.insert(column)
            columns.append(column)
        }
        return columns
    }

    // cosine of a one-hot seed vector (every given tag at equal weight, unit-
    // normalised) against every row's own unit-normalised weighted tag
    // vector. equivalent to: for each row, (sum of that row's raw weight at
    // each seed column) / (row norm x sqrt(seed tag count)) - the one-hot
    // seed vector's own norm is exactly sqrt(count), so this skips building
    // it explicitly
    func similarity(toColumns columns: [Int]) -> [Double] {
        guard !columns.isEmpty else { return [Double](repeating: 0, count: titleCount) }
        let seedColumns = Set(columns)
        let seedNorm = Float(columns.count).squareRoot()

        var result = [Double](repeating: 0, count: titleCount)
        tagWeights.withUnsafeBufferPointer { weights in
            tagIds.withUnsafeBufferPointer { ids in
                rowOffsets.withUnsafeBufferPointer { offsets in
                    for row in 0..<titleCount {
                        let lo = Int(offsets[row])
                        let hi = Int(offsets[row + 1])
                        guard hi > lo, rowNorms[row] > 0 else { continue }
                        var dot: Float = 0
                        for i in lo..<hi where seedColumns.contains(Int(ids[i])) {
                            dot += Float(weights[i])
                        }
                        guard dot > 0 else { continue }
                        result[row] = Double(dot / (rowNorms[row] * seedNorm))
                    }
                }
            }
        }
        return result
    }

    // row-to-row weighted cosine, for a resolved seed with its own real tag
    // vector - both sides use their actual per-tag weights (defining/core/
    // recurrent/...), not the one-hot approximation similarity(toColumns:)
    // uses for a virtual seed with no weight data. tags.py's own
    // similarity_to(seed_row), not similarity_to_virtual()
    func similarity(toRow seedRow: Int) -> [Double] {
        guard rowNorms[seedRow] > 0 else { return [Double](repeating: 0, count: titleCount) }

        var seedWeights: [Int: Float] = [:]
        rowOffsets.withUnsafeBufferPointer { offsets in
            tagIds.withUnsafeBufferPointer { ids in
                tagWeights.withUnsafeBufferPointer { weights in
                    let lo = Int(offsets[seedRow])
                    let hi = Int(offsets[seedRow + 1])
                    for i in lo..<hi { seedWeights[Int(ids[i])] = Float(weights[i]) }
                }
            }
        }
        guard !seedWeights.isEmpty else { return [Double](repeating: 0, count: titleCount) }

        var result = [Double](repeating: 0, count: titleCount)
        let seedNorm = rowNorms[seedRow]
        tagWeights.withUnsafeBufferPointer { weights in
            tagIds.withUnsafeBufferPointer { ids in
                rowOffsets.withUnsafeBufferPointer { offsets in
                    for row in 0..<titleCount {
                        let lo = Int(offsets[row])
                        let hi = Int(offsets[row + 1])
                        guard hi > lo, rowNorms[row] > 0 else { continue }
                        var dot: Float = 0
                        for i in lo..<hi {
                            if let seedWeight = seedWeights[Int(ids[i])] {
                                dot += Float(weights[i]) * seedWeight
                            }
                        }
                        guard dot > 0 else { continue }
                        result[row] = Double(dot / (rowNorms[row] * seedNorm))
                    }
                }
            }
        }
        return result
    }
}

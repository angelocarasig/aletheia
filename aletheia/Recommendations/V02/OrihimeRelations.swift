//
//  OrihimeRelations.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// relations/source_row.npy + related_row.npy: every sequel/prequel/spin-off/
// side-story/... edge, exported already bidirectional (heuresis' own
// Relations.build() stores both (row, other) and (other, row) per pair, so
// one direction here is the full picture) - a resolved seed excludes every
// row on its own list from its candidates, exactly candidates_for()'s own
// filter (blend.py), never gated by relation kind
struct OrihimeRelations: Sendable {
    private let relatedOf: [Int: [Int]]

    init(bundle: OrihimeBundle) throws {
        let sourceRows = try bundle.array("relations/source_row.npy", of: Int32.self)
        let relatedRows = try bundle.array("relations/related_row.npy", of: Int32.self)
        guard sourceRows.count == relatedRows.count else {
            throw RecommenderError.malformed(
                file: "relations", reason: "source_row and related_row counts differ")
        }

        var grouped: [Int: [Int]] = [:]
        sourceRows.withUnsafeBufferPointer { sources in
            relatedRows.withUnsafeBufferPointer { related in
                for i in 0..<sources.count {
                    grouped[Int(sources[i]), default: []].append(Int(related[i]))
                }
            }
        }
        relatedOf = grouped
    }

    func rows(relatedTo row: Int) -> [Int] {
        relatedOf[row] ?? []
    }
}

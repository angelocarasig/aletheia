//
//  OrihimePopularity.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// popularity.npy is a rank (1 = most popular), turned once into a 0...1
// percentile the blend can z-score like any other similarity - blend.py's
// own Blend.build(): order by rank, percentile = 1 - index/count
struct OrihimePopularity: Sendable {
    let percentile: [Double]

    init(bundle: OrihimeBundle) throws {
        let raw = try bundle.array("popularity.npy", of: Float16.self)
        let count = raw.count

        // a title with no rank sorts last (worst percentile), matching
        // np.nan_to_num(ranks, nan=1e12) rather than crashing a strict-weak-
        // ordering sort on NaN
        var ranks = [Double](repeating: 0, count: count)
        raw.withUnsafeBufferPointer { values in
            for i in 0..<count {
                let value = Double(values[i])
                ranks[i] = value.isNaN ? .greatestFiniteMagnitude : value
            }
        }

        let order = (0..<count).sorted { ranks[$0] < ranks[$1] }

        var result = [Double](repeating: 0, count: count)
        for (index, row) in order.enumerated() {
            result[row] = 1.0 - Double(index) / Double(count)
        }
        percentile = result
    }
}

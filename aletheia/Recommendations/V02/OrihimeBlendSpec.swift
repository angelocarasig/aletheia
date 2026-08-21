//
//  OrihimeBlendSpec.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// params/blend.json, read at runtime rather than hardcoded - a pack rebuild
// that retunes a weight or a gate parameter (blend/blend.py's Recipe) takes
// effect on next download, not on the next app update
struct OrihimeBlendSpec: Decodable, Sendable {
    let blocks: [Block]
    let popularityWeight: Double

    struct Block: Decodable, Sendable {
        let name: String
        let weight: Double
        // params values are always numbers in the pack (tag_count_full,
        // zero_chars, year_tau, ...) - decoded loosely since each block reads
        // only the keys it recognises, the same shape Recipe.param() reads on
        // the training side
        let params: [String: Double]

        func param(_ key: String, _ fallback: Double) -> Double {
            params[key] ?? fallback
        }
    }

    func block(_ name: String) -> Block? {
        blocks.first { $0.name == name }
    }

    static func load(bundle: OrihimeBundle) throws -> OrihimeBlendSpec {
        let data = try bundle.blob("params/blend.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(OrihimeBlendSpec.self, from: data)
        } catch {
            throw RecommenderError.malformed(file: "blend.json", reason: String(describing: error))
        }
    }
}

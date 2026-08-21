//
//  OrihimeCoverProjection.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// MobileCLIP's raw 512-d embedding, projected to the 128-d space the rails
// and vectors/cover.npy actually store - unit((v - mean) @ componentsT), per
// the pipeline's own scoring spec. mean/components come from
// params/cover-projection.npz, already loaded by OrihimeBundle
struct OrihimeCoverProjection: Sendable {
    private let mean: MappedArray<Float>
    private let components: MappedArray<Float>
    private let inputDimensions: Int
    private let outputDimensions: Int

    init(bundle: OrihimeBundle) throws {
        mean = try bundle.array("params/cover-projection.npz/mean.npy", of: Float.self)
        components = try bundle.array(
            "params/cover-projection.npz/components.npy", of: Float.self)
        inputDimensions = mean.count
        guard inputDimensions > 0, components.count % inputDimensions == 0 else {
            throw RecommenderError.malformed(
                file: "cover-projection.npz",
                reason: "components \(components.count) not a multiple of mean \(inputDimensions)")
        }
        outputDimensions = components.count / inputDimensions
    }

    func project(_ embedding: [Float]) throws -> [Float] {
        guard embedding.count == inputDimensions else {
            throw RecommenderError.malformed(
                file: "cover-projection.npz",
                reason: "embedding is \(embedding.count)-d, projection expects \(inputDimensions)-d")
        }

        var centred = embedding
        mean.withUnsafeBufferPointer { m in
            for i in 0..<centred.count { centred[i] -= m[i] }
        }

        var result = [Float](repeating: 0, count: outputDimensions)
        components.withUnsafeBufferPointer { c in
            for row in 0..<outputDimensions {
                var sum: Float = 0
                let base = row * inputDimensions
                for col in 0..<inputDimensions {
                    sum += centred[col] * c[base + col]
                }
                result[row] = sum
            }
        }

        let norm = result.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return result }
        return result.map { $0 / norm }
    }
}

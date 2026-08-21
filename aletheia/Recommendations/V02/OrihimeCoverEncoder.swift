//
//  OrihimeCoverEncoder.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import CoreML
import CoreGraphics
import Foundation
import Vision

// MobileCLIP-S0, run only for an unresolved seed's own cover - a resolved
// seed's cover contribution already lives precomputed in the rails table.
// the model takes a native Core ML image input (256x256 RGB, confirmed
// directly against the real .mlpackage's spec, not assumed) and hands back
// a 512-d embedding, which the caller projects to 128-d via
// params/cover-projection.npz - that projection is not this type's job,
// it has no access to the bundle's arrays
actor OrihimeCoverEncoder {
    private var model: MLModel?
    private var constraint: MLImageConstraint?
    private var failure: RecommenderError?

    // compute-unit assignment confirmed from the pipeline's own blend.json:
    // cpuAndNeuralEngine for the encoders, excluding GPU to keep it free for
    // the UI - the same reasoning V02Artifact.md already states
    private static let computeUnits: MLComputeUnits = .cpuAndNeuralEngine

    func prepare(bundle: OrihimeBundle) async throws {
        guard model == nil else { return }
        if let failure { throw failure }
        do {
            let packageURL = try bundle.modelURL("models/cover-mobileclip-s0.mlpackage")
            let compiledURL = try await OrihimeModelCache.compiledModel(
                named: "cover-mobileclip-s0",
                packId: bundle.packId,
                builtAt: bundle.manifest.builtAt,
                sourceURL: packageURL)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = Self.computeUnits
            let loaded = try MLModel(contentsOf: compiledURL, configuration: configuration)
            guard let imageConstraint = loaded.modelDescription.inputDescriptionsByName["image"]?
                .imageConstraint
            else {
                throw RecommenderError.malformed(
                    file: "cover-mobileclip-s0", reason: "no image input constraint")
            }
            model = loaded
            constraint = imageConstraint
        } catch let error as RecommenderError {
            failure = error
            throw error
        } catch {
            let wrapped = RecommenderError.malformed(
                file: "cover-mobileclip-s0", reason: String(describing: error))
            failure = wrapped
            throw wrapped
        }
    }

    // 512-d, raw - unit-normalising and projecting to 128-d is the caller's
    // job, done against params/cover-projection.npz which this type has no
    // access to
    func encode(_ image: CGImage) throws -> [Float] {
        guard let model, let constraint else { throw RecommenderError.unavailable }
        // MobileCLIP (like every CLIP family model) trains on resize-shorter-
        // side-then-center-crop, not stretch-to-fit - the omitted-options
        // default isn't documented by Apple, so this is spelled out rather
        // than left implicit
        let options: [MLFeatureValue.ImageOption: Any] = [
            .cropAndScale: VNImageCropAndScaleOption.centerCrop.rawValue
        ]
        let feature = try MLFeatureValue(cgImage: image, constraint: constraint, options: options)
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": feature])
        let output = try model.prediction(from: input)
        guard let embedding = output.featureValue(for: "final_emb_1")?.multiArrayValue else {
            throw RecommenderError.malformed(
                file: "cover-mobileclip-s0", reason: "no final_emb_1 output")
        }
        return (0..<embedding.count).map { Float(truncating: embedding[$0]) }
    }
}

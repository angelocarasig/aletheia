//
//  OrihimeTextEncoder.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import CoreML
import Foundation
import SentencepieceTokenizer

// intfloat/multilingual-e5-small, converted to Core ML. only runs for an
// unresolved seed's own title/synopsis - a resolved seed's contribution is
// already precomputed in the rails table
//
// SentencepieceTokenizer wraps the real Google SentencePiece C++ engine
// (jkrukowski/swift-sentencepiece), not a reimplementation - the precompiled
// charsmap normalisation XLM-R's tokenizer.json declares happens for free
// inside its encode() call, which is exactly why this dependency was chosen
// over huggingface/swift-transformers (its Unigram normalizer is a known-
// incomplete stub for exactly this case, confirmed against its source)
actor OrihimeTextEncoder {
    // confirmed directly against the real .mlpackage: input_ids/attention_mask
    // are [1, 512] Int32, fixed (ShapeFlexibility: none) - not a runtime choice
    private static let sequenceLength = 512
    private static let computeUnits: MLComputeUnits = .cpuAndNeuralEngine

    private var model: MLModel?
    private var tokenizer: SentencepieceTokenizer?
    private var failure: RecommenderError?

    func prepare(bundle: OrihimeBundle) async throws {
        guard model == nil else { return }
        if let failure { throw failure }
        do {
            let packageURL = try bundle.modelURL("models/text-e5-small.mlpackage")
            let compiledURL = try await OrihimeModelCache.compiledModel(
                named: "text-e5-small",
                packId: bundle.packId,
                builtAt: bundle.manifest.builtAt,
                sourceURL: packageURL)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = Self.computeUnits
            model = try MLModel(contentsOf: compiledURL, configuration: configuration)

            // SentencepieceTokenizer opens the file directly (it's a C++
            // library, not a Data-based reader) - the one other model
            // artifact besides the .mlpackage itself that needs modelURL(_:)
            // rather than array(_:of:)/blob(_:)
            let tokenizerURL = try bundle.modelURL(
                "models/text-tokenizer/sentencepiece.bpe.model")
            tokenizer = try SentencepieceTokenizer(modelPath: tokenizerURL.path)
        } catch let error as RecommenderError {
            failure = error
            throw error
        } catch {
            let wrapped = RecommenderError.malformed(
                file: "text-e5-small", reason: String(describing: error))
            failure = wrapped
            throw wrapped
        }
    }

    // 384-d, raw - mean-centring against params/text-*-mean.npy is the
    // caller's job, this type has no access to the bundle's arrays
    func encode(_ text: String) throws -> [Float] {
        guard let model, let tokenizer else { throw RecommenderError.unavailable }
        let (inputIds, attentionMask) = try tokenize(text, with: tokenizer)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])
        let output = try model.prediction(from: input)
        guard let embedding = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw RecommenderError.malformed(file: "text-e5-small", reason: "no embedding output")
        }
        return (0..<embedding.count).map { Float(truncating: embedding[$0]) }
    }

    // XLM-RoBERTa's own convention - <s> tokens </s> - which encode() does
    // not add on its own; it hands back raw sentencepiece ids only. "query: "
    // is the prefix e5 requires, confirmed via params/blend.json's
    // virtual_seed.text_prefix, not a guess
    private func tokenize(
        _ text: String, with tokenizer: SentencepieceTokenizer
    ) throws -> (MLMultiArray, MLMultiArray) {
        let pieces = try tokenizer.encode("query: " + text)
        let budget = Self.sequenceLength - 2
        let truncated = pieces.count > budget ? Array(pieces.prefix(budget)) : pieces

        var ids = [tokenizer.bosTokenId] + truncated + [tokenizer.eosTokenId]
        var mask = [Int](repeating: 1, count: ids.count)
        let padCount = Self.sequenceLength - ids.count
        if padCount > 0 {
            ids.append(contentsOf: repeatElement(tokenizer.padTokenId, count: padCount))
            mask.append(contentsOf: repeatElement(0, count: padCount))
        }

        let inputIds = try MLMultiArray(
            shape: [1, NSNumber(value: Self.sequenceLength)], dataType: .int32)
        let attentionMask = try MLMultiArray(
            shape: [1, NSNumber(value: Self.sequenceLength)], dataType: .int32)
        for i in 0..<Self.sequenceLength {
            inputIds[i] = NSNumber(value: ids[i])
            attentionMask[i] = NSNumber(value: mask[i])
        }
        return (inputIds, attentionMask)
    }
}

//
//  ModelManifest.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// the two manifests that describe the model bundle. the scoring half and the
// display half are separate documents on purpose: the metadata pack is derived
// from the catalogue rather than the fitted model, so it can be regenerated,
// verified or dropped without any of it touching a score
struct ModelManifest: Decodable, Sendable {
    let formatVersion: Int
    let titleCount: Int
    let tagVocabSize: Int
    let types: [String]
    let orientations: [String]
    let ratingLadder: [String]
    let yearUnknown: Int
    let constants: Constants
    let files: [String: FileSpec]

    struct Constants: Decodable, Sendable {
        let wTag: Float
        let wEmbed: Float
        let wTfidf: Float
        let wYear: Float
        let yearTau: Float
        let tagSaturate: Float
        let ancestorDecay: Float
        let typeBoost: Float
        let confidenceStrong: Float
        let confidenceFair: Float
    }
}

struct MetadataManifest: Decodable, Sendable {
    let metadataVersion: Int
    let formatVersion: Int
    let titleCount: Int
    let statuses: [String]
    let files: [String: FileSpec]
}

// one shape for both. every field past the first three is present on some files
// and absent on others - a blob entry carries no arrays at all - so they are
// optional here rather than modelled per file type, which would be six structs
// to express the same thing
struct FileSpec: Decodable, Sendable {
    let arrays: [ArraySpec]
    let order: [String]
    let sha256: String
    let fileBytes: Int

    let valueScale: Double?
    let rows: Int?
    let dims: Int?
    let blob: String?

    // the array named `name`, or nil. `order` and `arrays` are parallel: the
    // exporter writes them together and the manifest's whole purpose is that
    // nothing needs parsing to be read
    func array(_ name: String) -> ArraySpec? {
        guard let i = order.firstIndex(of: name), i < arrays.count else { return nil }
        return arrays[i]
    }
}

struct ArraySpec: Decodable, Sendable {
    let dtype: String
    let count: Int
    let offset: Int
    let bytes: Int
}

// the numpy dtype names the exporter writes, bound to the Swift types that read
// them. this is the check that matters: an array's element type is stated in the
// manifest, so reading uint16 indices as uint32 is caught rather than producing
// half as many plausible-looking numbers
protocol ModelScalar {
    static var dtype: String { get }
}

extension UInt8: ModelScalar { static var dtype: String { "uint8" } }
extension UInt16: ModelScalar { static var dtype: String { "uint16" } }
extension UInt32: ModelScalar { static var dtype: String { "uint32" } }
extension UInt64: ModelScalar { static var dtype: String { "uint64" } }
extension Int8: ModelScalar { static var dtype: String { "int8" } }
extension Int16: ModelScalar { static var dtype: String { "int16" } }
extension Int32: ModelScalar { static var dtype: String { "int32" } }
extension Float: ModelScalar { static var dtype: String { "float32" } }

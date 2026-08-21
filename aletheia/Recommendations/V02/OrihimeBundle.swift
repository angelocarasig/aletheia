//
//  OrihimeBundle.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import BackgroundAssets
import Foundation
import System

// numpy's dtype code (without the byte-order prefix NumpyHeader already stripped) bound to
// the Swift type that reads it - the same role ModelScalar plays for v01, kept separate
// because the two packs' manifests name dtypes with entirely different vocabularies (v01's
// exporter writes "uint8"/"float32"; numpy's own headers write "u1"/"f4")
protocol NumpyScalar {
    static var numpyDtype: String { get }
}

extension Int8: NumpyScalar { static var numpyDtype: String { "i1" } }
extension Int16: NumpyScalar { static var numpyDtype: String { "i2" } }
extension Int32: NumpyScalar { static var numpyDtype: String { "i4" } }
extension Int64: NumpyScalar { static var numpyDtype: String { "i8" } }
extension UInt8: NumpyScalar { static var numpyDtype: String { "u1" } }
extension Float: NumpyScalar { static var numpyDtype: String { "f4" } }
extension Float16: NumpyScalar { static var numpyDtype: String { "f2" } }

struct OrihimeBundle: Sendable {
    static let supportedPackSchema = 2

    let manifest: OrihimeManifest
    private let mapped: [String: Data]

    enum Source: Sendable {
        case appBundle(Foundation.Bundle = .main)
        case assetPack(id: String, root: String)
    }

    // the pack's two .npz files and the arrays inside each one the loader maps eagerly -
    // npz members have no manifest entry of their own (only the container does), so this is
    // the pack's one fixed, known-ahead-of-time layout rather than something derived
    private static let npzMembers: [String: [String]] = [
        "models/student/student-linear.npz": ["flag_weights.npy", "thresholds.npy"],
        "params/cover-projection.npz": ["mean.npy", "components.npy"],
    ]

    static func load(from source: Source) throws -> OrihimeBundle {
        guard let manifestData = try read("manifest.json", from: source) else {
            throw RecommenderError.unavailable
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest: OrihimeManifest
        do {
            manifest = try decoder.decode(OrihimeManifest.self, from: manifestData)
        } catch {
            throw RecommenderError.malformed(file: "manifest.json", reason: String(describing: error))
        }
        guard manifest.packSchema == supportedPackSchema else {
            throw RecommenderError.unsupportedFormat(
                found: manifest.packSchema, supported: supportedPackSchema)
        }

        var mapped: [String: Data] = [:]

        for (name, spec) in manifest.files where spec.shape != nil {
            guard let data = try read(name, from: source) else {
                throw RecommenderError.malformed(file: name, reason: "not in the pack")
            }
            guard data.count == spec.bytes else {
                throw RecommenderError.truncated(file: name, expected: spec.bytes, found: data.count)
            }
            try validate(name, data: data, spec: spec)
            mapped[name] = data
        }

        for (npzName, members) in npzMembers {
            guard let npzData = try read(npzName, from: source) else {
                throw RecommenderError.malformed(file: npzName, reason: "not in the pack")
            }
            let extracted = try NumpyZipReader.entries(in: npzData, named: Set(members))
            for member in members {
                guard let data = extracted[member] else {
                    throw RecommenderError.malformed(
                        file: "\(npzName)/\(member)", reason: "not in the archive")
                }
                mapped["\(npzName)/\(member)"] = data
            }
        }

        return OrihimeBundle(manifest: manifest, mapped: mapped)
    }

    func array<Element: NumpyScalar>(
        _ file: String, of type: Element.Type = Element.self
    ) throws -> MappedArray<Element> {
        guard let data = mapped[file] else {
            throw RecommenderError.malformed(file: file, reason: "not mapped")
        }
        let header = try NumpyHeader.parse(data)
        // b1 (numpy bool) is one byte, same as u1 - excluded.npy is the pack's only bool
        // array and reading it as UInt8 (0/1) avoids a dedicated Bool conformance, whose
        // in-memory size Swift doesn't guarantee matches numpy's on-disk byte exactly
        let matches =
            header.dtype == Element.numpyDtype
            || (Element.numpyDtype == "u1" && header.dtype == "b1")
        guard matches else {
            throw RecommenderError.malformed(
                file: file, reason: "\(file) is \(header.dtype), asked for \(Element.numpyDtype)")
        }
        guard header.dataOffset % MemoryLayout<Element>.alignment == 0 else {
            throw RecommenderError.misaligned(file: file, array: file)
        }
        let count = header.shape.reduce(1, *)
        return MappedArray(data: data, offset: header.dataOffset, count: count)
    }

    private static func validate(_ name: String, data: Data, spec: OrihimeManifest.FileSpec) throws {
        guard let expectedShape = spec.shape, let expectedDtype = spec.dtype else { return }
        let header = try NumpyHeader.parse(data)
        guard header.shape == expectedShape else {
            throw RecommenderError.malformed(
                file: name,
                reason: "manifest says shape \(expectedShape), header says \(header.shape)")
        }
        let strippedExpected = expectedDtype.drop { "<>|=".contains($0) }
        guard header.dtype == strippedExpected else {
            throw RecommenderError.malformed(
                file: name,
                reason: "manifest says dtype \(expectedDtype), header says \(header.dtype)")
        }
    }

    private static func read(_ file: String, from source: Source) throws -> Data? {
        switch source {
        case .appBundle(let bundle):
            let name = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        case .assetPack(let id, let root):
            do {
                return try AssetPackManager.shared.contents(
                    at: FilePath("\(root)/\(file)"),
                    searchingInAssetPackWithID: id,
                    options: .mappedIfSafe)
            } catch {
                return nil
            }
        }
    }
}

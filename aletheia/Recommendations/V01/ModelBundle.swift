//
//  ModelBundle.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import BackgroundAssets
import Foundation
import System

// the bytes, and nothing about recommending. it decodes both manifests, refuses a
// version it does not know, memory-maps every file and hands out typed views at
// the offsets the manifest states. its whole job is that a UInt16 array at offset
// 1211580 of tags.bin is 5142943 elements and not a guess
//
// the files are never read into memory. 263 MB resident is not survivable on a
// phone, and mapping makes construction nearly free - nothing is paged in until
// something is touched, and the pages can be evicted again under pressure
struct ModelBundle: Sendable {
    static let supportedFormatVersion = 1
    static let supportedMetadataVersion = 1

    let manifest: ModelManifest
    let metadata: MetadataManifest?
    // tagvocab.json is a flat dictionary, not a typed array - TagVocabulary
    // decodes it itself, so this is handed over raw rather than through the
    // array()/blob() accessors below
    let tagVocabularyData: Data

    private let mapped: [String: Data]

    var titleCount: Int { manifest.titleCount }

    // where a bundle's files come from. .appBundle is dev/preview convenience
    // only - shipped builds source from a downloaded pack, never Bundle.main,
    // since Resources/Models is gitignored and empty on every machine but the
    // one that built the fixture
    enum Source: Sendable {
        case appBundle(Foundation.Bundle = .main)
        // root is the fileSelectors directory ba-package bakes into the .aar -
        // preserved as a literal subfolder, not flattened
        case assetPack(id: String, root: String)
    }

    // the namespace under a source is flat: files are resolved by name alone,
    // relative to the bundle root or the pack's fileSelectors directory
    static func load(from source: Source) throws -> ModelBundle {
        guard let manifestData = try read("manifest.json", from: source) else {
            throw RecommenderError.unavailable
        }

        let manifest: ModelManifest = try decode(manifestData, file: "manifest.json")
        guard manifest.formatVersion == supportedFormatVersion else {
            throw RecommenderError.unsupportedFormat(
                found: manifest.formatVersion,
                supported: supportedFormatVersion)
        }

        // the display pack is optional by construction - it feeds no arithmetic,
        // so a bundle without it still scores. a pack from a different build is
        // not optional, though: its arrays are positional against this row order
        // and a mismatched titleCount means every field describes the wrong series
        var metadata: MetadataManifest?
        if let metadataData = try read("metadata.json", from: source) {
            let pack: MetadataManifest = try decode(metadataData, file: "metadata.json")
            guard pack.metadataVersion == supportedMetadataVersion else {
                throw RecommenderError.unsupportedFormat(
                    found: pack.metadataVersion,
                    supported: supportedMetadataVersion)
            }
            guard pack.titleCount == manifest.titleCount else {
                throw RecommenderError.malformed(
                    file: "metadata.json",
                    reason: "describes \(pack.titleCount) rows, model has \(manifest.titleCount)")
            }
            metadata = pack
        }

        let specs = manifest.files.merging(metadata?.files ?? [:], uniquingKeysWith: { a, _ in a })

        // a blob is named by the spec that indexes it, and in the core manifest
        // it has no entry of its own - titles.bin declares `blob: titles.blob`
        // and nothing else mentions it. mapping only the declared entries leaves
        // every paired blob unmapped, which the metadata pack happens to hide
        // because its blobs do carry their own entries
        let names = Set(specs.keys).union(specs.values.compactMap(\.blob))

        var mapped: [String: Data] = [:]
        for name in names {
            guard let data = try read(name, from: source) else {
                throw RecommenderError.malformed(file: name, reason: "not in the bundle")
            }
            // size rather than sha256, and only where a size was stated
            if let expected = specs[name]?.fileBytes, data.count != expected {
                throw RecommenderError.truncated(
                    file: name,
                    expected: expected,
                    found: data.count)
            }
            mapped[name] = data
        }

        // not declared in either manifest's files dict - it is TagVocabulary's
        // own file, not a typed array, so it never enters names/mapped above
        guard let tagVocabularyData = try read("tagvocab.json", from: source) else {
            throw RecommenderError.malformed(file: "tagvocab.json", reason: "missing")
        }

        return ModelBundle(
            manifest: manifest, metadata: metadata,
            tagVocabularyData: tagVocabularyData, mapped: mapped)
    }

    // mapped, not loaded - both an app-bundle resource and an asset-pack file
    // support .mappedIfSafe, so construction stays nearly free either way.
    // nil means "not present" (a fresh checkout's empty bundle, or a pack that
    // hasn't downloaded yet) rather than a hard failure - only load() above
    // knows whether the caller is asking for the required manifest or an
    // optional display pack
    private static func read(_ file: String, from source: Source) throws -> Data? {
        switch source {
        case .appBundle(let bundle):
            guard let fileURL = url(for: file, in: bundle) else { return nil }
            return try Data(contentsOf: fileURL, options: .mappedIfSafe)
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

    // a typed view of one named array - the guard below is what stops a uint16
    // column being silently read as uint32
    func array<Element: ModelScalar>(
        _ file: String,
        _ name: String,
        of type: Element.Type = Element.self
    ) throws -> MappedArray<Element> {
        guard let spec = self.spec(for: file) else {
            throw RecommenderError.malformed(file: file, reason: "not in either manifest")
        }
        guard let array = spec.array(name) else {
            throw RecommenderError.malformed(file: file, reason: "no array named \(name)")
        }
        guard array.dtype == Element.dtype else {
            throw RecommenderError.malformed(
                file: file, reason: "\(name) is \(array.dtype), asked for \(Element.dtype)")
        }
        guard let data = mapped[file] else {
            throw RecommenderError.malformed(file: file, reason: "not mapped")
        }
        // a mapped file starts page-aligned and every offset the exporter writes
        // is a multiple of its element size, so this holds today. it is checked
        // rather than assumed because a future array added ahead of this one
        // would break it silently, and an unaligned load is undefined behaviour
        // rather than a wrong number
        guard array.offset % MemoryLayout<Element>.alignment == 0 else {
            throw RecommenderError.misaligned(file: file, array: name)
        }
        return MappedArray(data: data, offset: array.offset, count: array.count)
    }

    // a utf-8 blob paired with an offsets array: titles, covers, synopses and the
    // pooled names all take this shape
    func blob(_ file: String) throws -> Data {
        guard let data = mapped[file] else {
            throw RecommenderError.malformed(file: file, reason: "not mapped")
        }
        return data
    }

    private func spec(for file: String) -> FileSpec? {
        manifest.files[file] ?? metadata?.files[file]
    }

    private static func url(for file: String, in bundle: Foundation.Bundle) -> URL? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext)
    }

    private static func decode<T: Decodable>(_ data: Data, file: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RecommenderError.malformed(file: file, reason: String(describing: error))
        }
    }
}

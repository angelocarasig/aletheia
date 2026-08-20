//
//  ModelBundle.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

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

    private let mapped: [String: Data]

    var titleCount: Int { manifest.titleCount }

    // the bundle namespace is flat: resources land at the app root whatever
    // directory they sat in under Resources/, which step 1 confirmed by shipping
    // fixtures/hash.json as hash.json. so files are resolved by name alone
    static func load(in bundle: Foundation.Bundle = .main) throws -> ModelBundle {
        guard let manifestURL = url(for: "manifest.json", in: bundle) else {
            throw RecommenderError.unavailable
        }

        let manifest: ModelManifest = try decode(manifestURL, as: ModelManifest.self)
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
        if let metadataURL = url(for: "metadata.json", in: bundle) {
            let pack: MetadataManifest = try decode(metadataURL, as: MetadataManifest.self)
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
            guard let fileURL = url(for: name, in: bundle) else {
                throw RecommenderError.malformed(file: name, reason: "not in the bundle")
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            // size rather than sha256, and only where a size was stated
            if let expected = specs[name]?.fileBytes, data.count != expected {
                throw RecommenderError.truncated(
                    file: name,
                    expected: expected,
                    found: data.count)
            }
            mapped[name] = data
        }

        return ModelBundle(manifest: manifest, metadata: metadata, mapped: mapped)
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

    private static func decode<T: Decodable>(_ url: URL, as type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: try Data(contentsOf: url))
        } catch {
            throw RecommenderError.malformed(
                file: url.lastPathComponent,
                reason: String(describing: error))
        }
    }
}

// a window onto mapped bytes. it holds the Data rather than a pointer, so the
// mapping outlives every use and nothing escapes a withUnsafeBytes closure -
// which is the one way to read this safely, however tempting the alternative
// looks in a hot loop
struct MappedArray<Element>: Sendable {
    private let data: Data
    private let offset: Int
    let count: Int

    init(data: Data, offset: Int, count: Int) {
        self.data = data
        self.offset = offset
        self.count = count
    }

    func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows
        -> R
    {
        try data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: offset)
            return try body(
                UnsafeBufferPointer(
                    start: base.assumingMemoryBound(to: Element.self),
                    count: count))
        }
    }

    subscript(index: Int) -> Element {
        withUnsafeBufferPointer { $0[index] }
    }
}

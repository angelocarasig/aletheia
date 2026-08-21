//
//  OrihimeModelCache.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import CoreML
import Foundation

// compiles a .mlpackage once and persists the .mlmodelc result, so the
// compile cost (real - MLModel.compileModel(at:) is not instant) is paid
// once per pack build rather than every cold start. see V02Integration.md
// for why this is on-device compile from source rather than a precompiled
// .mlmodelc shipped in the pack
//
// keyed by packId + the pack's own built_at, not just a model name - this
// app hit two real stale-cache bugs against a downloaded pack already this
// session (Background Assets serving an old manifest, an old extracted
// pack), both from caching something keyed on identity alone rather than on
// the specific build. a rebuilt pack with the same packId must not silently
// reuse a compiled model from the previous build
enum OrihimeModelCache {
    static func compiledModel(
        named name: String, packId: String, builtAt: String, sourceURL: URL
    ) async throws -> URL {
        let directory = try cacheDirectory()
        let key = sanitized("\(packId)-\(builtAt)-\(name)")
        let destination = directory.appending(path: "\(key).mlmodelc")

        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        try? removeStaleCompiledModels(for: name, packId: packId, in: directory, keeping: key)

        let compiled = try await MLModel.compileModel(at: sourceURL)
        // compileModel(at:) writes to a system temp location the OS may
        // reclaim at any time - copying into the app's own cache directory
        // is what makes this reusable across launches at all
        try FileManager.default.copyItem(at: compiled, to: destination)
        return destination
    }

    // a stale compiled model from a previous build of the same pack (or the
    // same model name under an older packId) is dead weight, not a fallback
    // - nothing reads it once a fresher one exists
    private static func removeStaleCompiledModels(
        for name: String, packId: String, in directory: URL, keeping key: String
    ) throws {
        let prefix = sanitized("\(packId)-")
        let suffix = sanitized("-\(name)")
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        for entry in entries {
            let stem = entry.deletingPathExtension().lastPathComponent
            guard stem != key, stem.hasPrefix(prefix), stem.hasSuffix(suffix) else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func cacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let directory = base.appending(path: "OrihimeModels", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitized(_ value: String) -> String {
        value.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    }
}

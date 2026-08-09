//
//  AssetStoring.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation

// a remote thing worth keeping on disk where the key is supplied by the caller
// rather than derived from the urls, which is what lets a cover (keyed by its
// own url) and a chapter (keyed by origin and slug, with many page urls) be the
// same shape
struct Asset: Sendable {
    let key: String
    let parts: [URL]
    let folder: URL

    // whatever the source itself would send - referer, pinned agent, and the
    // cookies it already holds. a referer alone was enough for covers and is not
    // enough for pages: behind cloudflare the missing cookie comes back as a
    // 200 text/html challenge, which store() then refuses as "not an image".
    // built once by SourceService.requestHeaders so no caller composes its own
    let headers: [String: String]

    // many parts land as a directory, one lands as a file
    var collected: Bool { parts.count > 1 }
}

extension Asset {
    var location: URL {
        let digest = Checksum.hex(key)
        return folder
            .appending(path: String(digest.prefix(2)))
            .appending(path: digest)
    }

    // zero padded so lexicographic order is page order
    func part(_ index: Int) -> URL {
        collected ? location.appending(path: String(format: "%04d", index)) : location
    }

    var directory: URL {
        collected ? location : location.deletingLastPathComponent()
    }
}

protocol AssetStoring: Sendable {
    func store(_ asset: Asset, progress: (@Sendable (Int, Int) -> Void)?) async throws -> String
    func resolve(_ relative: String?) -> URL?
    func sweep(_ folder: URL, keeping live: Set<String>) throws -> Int
}

extension AssetStoring {
    func store(_ asset: Asset) async throws -> String {
        try await store(asset, progress: nil)
    }
}

enum AssetError: DescribableError {
    case notAnImage(URL)

    var errorDescription: String? { "Couldn't Save Image" }
    var failureReason: String? { "The file that came back wasn't an image." }

    // the bytes at that url will not become an image on a second attempt
    var isRetryable: Bool { false }
}

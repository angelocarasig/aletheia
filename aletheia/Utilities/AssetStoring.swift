//
//  AssetStoring.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation

// key is caller-supplied, not derived from the urls - lets a cover (keyed by
// its own url) and a chapter (keyed by origin and slug, many page urls) share
// this shape
struct Asset: Sendable {
    let key: String
    let parts: [URL]
    let folder: URL

    // a referer alone is enough for covers but not pages - behind cloudflare
    // the missing cookie comes back as a 200 text/html challenge, which
    // store() then refuses as "not an image". built once by
    // SourceService.requestHeaders so no caller composes its own
    let headers: [String: String]

    var collected: Bool { parts.count > 1 }
}

extension Asset {
    var location: URL {
        let digest = Checksum.hex(key)
        return
            folder
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

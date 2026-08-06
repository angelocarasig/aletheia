//
//  AssetStore.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation

struct AssetStore: AssetStoring {
    private let network: NetworkConfiguration
    private let throttler: RequestThrottler
    private let log: AppLog

    // its own throttler rather than the shared one: that is tuned for json with a
    // three second timeout, which half a megabyte of cover blows through on any
    // congested connection
    init(network: NetworkConfiguration, log: AppLog = .shared) {
        self.network = network
        self.throttler = RequestThrottler(
            maxConcurrent: Limits.concurrent,
            staggerDelay: Limits.stagger,
            timeout: Limits.timeout
        )
        self.log = log
    }

    private enum Limits {
        static let concurrent = 3
        static let stagger: Duration = .milliseconds(250)
        static let timeout: Duration = .seconds(30)
    }

    func store(_ asset: Asset, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(at: asset.directory, withIntermediateDirectories: true)

        var written: URL?

        for (index, remote) in asset.parts.enumerated() {
            try Task.checkCancellation()

            // the extension is only known once the bytes arrive, so a stored file
            // is found by its stem rather than by an exact name
            let stem = asset.part(index)
            if let existing = Self.existing(stem) {
                written = existing
                progress?(index + 1, asset.parts.count)
                continue
            }

            var headers = ["User-Agent": Constants.Network.userAgent]
            if let referer = asset.referer {
                headers["Referer"] = referer.absoluteString
            }

            let data: Data = try await throttler.execute { [network] in
                try await network.get(url: remote, headers: headers)
            }

            // a status code is not enough. cloudflare interstitials and hotlink
            // blocks come back 200 text/html, and persisting one would set a path
            // that claims success, so the remote fallback would never fire again
            guard let format = Self.format(of: data) else { throw AssetError.notAnImage(remote) }

            let destination = stem.appendingPathExtension(format)
            try data.write(to: destination, options: .atomic)
            written = destination

            #if DEBUG
            // absolute on purpose - this is the simulator container path, so it
            // can be pasted straight into open(1) or the finder
            log.log("stored \(destination.path(percentEncoded: false))", category: "assets")
            #endif

            progress?(index + 1, asset.parts.count)
        }

        // a collected asset is named by its directory; a single one by the file
        // that actually landed, extension included
        return Constants.Paths.relative(asset.collected ? asset.location : (written ?? asset.location))
    }

    private static func existing(_ stem: URL) -> URL? {
        let manager = FileManager.default
        let name = stem.lastPathComponent
        let entries = (try? manager.contentsOfDirectory(
            at: stem.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )) ?? []

        return entries.first { $0.lastPathComponent == name || $0.lastPathComponent.hasPrefix("\(name).") }
    }

    func resolve(_ relative: String?) -> URL? {
        Constants.Paths.resolve(relative)
    }

    // fixed depth on purpose. recursing would surface a collected asset's
    // individual parts, none of which the database names, and delete every page
    // of every downloaded chapter
    func sweep(_ folder: URL, keeping live: Set<String>) throws -> Int {
        let manager = FileManager.default
        let shards = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var removed = 0

        for shard in shards {
            let entries = (try? manager.contentsOfDirectory(at: shard, includingPropertiesForKeys: nil)) ?? []

            for entry in entries where !live.contains(Constants.Paths.relative(entry)) {
                do {
                    try manager.removeItem(at: entry)
                    removed += 1
                } catch {
                    log.log("could not remove \(entry.lastPathComponent) — \(error)", category: "assets")
                }
            }
        }

        return removed
    }

    // doubles as the validity check - an unrecognised header means the response
    // was not an image and must not be persisted
    private static func format(of data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data.prefix(12))

        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        if Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70] {
            return Array(bytes[8..<12]) == [0x61, 0x76, 0x69, 0x66] ? "avif" : "heic"
        }

        return nil
    }
}

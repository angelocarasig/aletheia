//
//  Paths.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import Foundation

extension Constants {
    enum Paths {
        static var database: URL {
            directory("Database").appendingPathComponent("aletheia.db")
        }

        // let, not a computed var - excluding a directory from backup is a
        // write, and these are read often enough that repeating it is waste
        static let downloads: URL = directory("Downloads", backedUp: false)

        static let covers: URL = directory("Covers", backedUp: false)

        // diagnostics about this install - restoring last month's log onto a
        // new device would be actively confusing
        static let logs: URL = directory("Logs", backedUp: false)

        // the container carries a uuid that changes across installs, so an
        // absolute path rots - paths are stored container-relative.
        //
        // the trailing slash is not cosmetic: a url with a directory hint (what
        // contentsOfDirectory hands back for a folder) keeps it in
        // path(percentEncoded:), while a path built by appending components does
        // not. a chapter is stored as a directory, so without this the two
        // spellings never compare equal and the sweep reads every downloaded
        // chapter as an orphan
        static func relative(_ url: URL) -> String {
            let base = containerURL.path(percentEncoded: false)
            let full = url.path(percentEncoded: false)
            guard full.hasPrefix(base) else { return trimmed(full) }
            return trimmed(String(full.dropFirst(base.count).drop { $0 == "/" }))
        }

        // nil covers both "never stored" and "file has since gone" - callers
        // fall back to the remote url either way
        static func resolve(_ relative: String?) -> URL? {
            guard let relative, !relative.isEmpty else { return nil }
            let url = containerURL.appending(path: relative)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
                ? url : nil
        }
    }

    // MARK: Private

    private static func trimmed(_ path: String) -> String {
        var path = path
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static let containerURL: URL = {
        guard
            let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Constants.App.identifier
            )
        else {
            fatalError("App Group '\(Constants.App.identifier)' not configured.")
        }

        return url
    }()

    // backedUp: false for anything a source can serve again - icloud quota
    // spent on gigabytes of re-fetchable page images buys the user nothing.
    // the database, which holds what cannot be re-fetched, stays backed up
    private static func directory(_ name: String, backedUp: Bool = true) -> URL {
        var url = containerURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )

        if !backedUp {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }

        return url
    }

}

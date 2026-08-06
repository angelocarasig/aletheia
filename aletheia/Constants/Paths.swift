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
        
        static var downloads: URL {
            directory("Downloads")
        }
        
        static var covers: URL {
            directory("Covers")
        }

        // stored paths are container-relative: the container itself carries a uuid
        // that changes across installs, so an absolute one rots
        static func relative(_ url: URL) -> String {
            let base = containerURL.path(percentEncoded: false)
            let full = url.path(percentEncoded: false)
            guard full.hasPrefix(base) else { return full }
            return String(full.dropFirst(base.count).drop { $0 == "/" })
        }

        // nil when nothing was ever stored, and nil when the file has since gone -
        // callers fall back to the remote url either way
        static func resolve(_ relative: String?) -> URL? {
            guard let relative, !relative.isEmpty else { return nil }
            let url = containerURL.appending(path: relative)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
    }
    
    // MARK: Private
    
    private static let containerURL: URL = {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.App.identifier
        ) else {
            fatalError("App Group '\(Constants.App.identifier)' not configured.")
        }

        return url
    }()
    
    private static func directory(_ name: String) -> URL {
        let url = containerURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        
        return url
    }
    
}

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
    }
    
    // MARK: Private
    
    private static let containerUrl: URL = {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.App.identifier
        ) else {
            fatalError("App Group '\(Constants.App.identifier)' not configured.")
        }

        return url
    }()
    
    private static func directory(_ name: String) -> URL {
        let url = containerUrl.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        
        return url
    }
    
}

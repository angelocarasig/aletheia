//
//  DatabaseVersion.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

/// semantic version for the database, used for naming conventions in migrations
struct DatabaseVersion: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String {
        "v\(major).\(minor).\(patch)"
    }

    init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: DatabaseVersion, rhs: DatabaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    func createMigrationName(description: String) -> String {
        "\(self.description) \(description)".replacingOccurrences(of: " ", with: "_")
    }
}

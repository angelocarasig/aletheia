//
//  SourceFilter.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

/// a filter a source declares it supports (in its descriptor). the search UI
/// renders these generically; the user's choices come back as [FilterSelection].
enum SourceFilter: Sendable, Hashable {
    case text(id: String, name: String)
    case number(id: String, name: String)
    case select(id: String, name: String, options: [Option])
    case multiSelect(id: String, name: String, options: [Option], canExclude: Bool)

    /// a single option: a display label paired with the backend id sent in requests.
    struct Option: Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let nsfw: Bool

        init(id: String, name: String, nsfw: Bool = false) {
            self.id = id
            self.name = name
            self.nsfw = nsfw
        }
    }

    /// a declared sort axis + its options and defaults.
    struct Sort: Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let options: [Option]
        let defaultIndex: Int
        let defaultAscending: Bool
    }
}

// MARK: - Stable fingerprint (deterministic; feeds SourceDescriptor.fingerprint)

extension SourceFilter {
    var fingerprint: String {
        switch self {
        case let .text(id, name):
            return "text:\(id):\(name)"
        case let .number(id, name):
            return "number:\(id):\(name)"
        case let .select(id, name, options):
            return "select:\(id):\(name):\(options.fingerprint)"
        case let .multiSelect(id, name, options, canExclude):
            return "multi:\(id):\(name):\(canExclude):\(options.fingerprint)"
        }
    }
}

extension SourceFilter.Sort {
    var fingerprint: String {
        "\(id):\(name):\(defaultIndex):\(defaultAscending):\(options.fingerprint)"
    }
}

extension Array where Element == SourceFilter.Option {
    var fingerprint: String {
        map { "\($0.id)=\($0.name)" }.joined(separator: ",")
    }
}

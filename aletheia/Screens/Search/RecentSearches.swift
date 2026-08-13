//
//  RecentSearches.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation

enum RecentSearches {
    private static let limit = 8
    private static let minimum = 2

    static var entries: [String] {
        UserDefaults.standard.stringArray(forKey: Preferences.Key.recentSearches) ?? []
    }

    // a search is filed once per debounced pause, so typing "solo" arrives here
    // as "so", then "sol", then "solo". an entry the new query grew out of is
    // dropped rather than kept beside it, which also covers the exact repeat -
    // a string is a prefix of itself
    static func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimum else { return }

        let lowered = trimmed.lowercased()
        var kept = entries.filter { !lowered.hasPrefix($0.lowercased()) }
        kept.insert(trimmed, at: 0)

        write(Array(kept.prefix(limit)))
    }

    static func remove(_ query: String) {
        write(entries.filter { $0 != query })
    }

    static func clear() {
        write([])
    }

    private static func write(_ entries: [String]) {
        UserDefaults.standard.set(entries, forKey: Preferences.Key.recentSearches)
    }
}

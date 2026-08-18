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

    // debounced typing files partial queries too - drop entries that are a prefix
    // of the new one so "sol" doesn't linger beside "solo"
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

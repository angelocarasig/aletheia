//
//  MetadataRefreshInterval.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// the raw values are persisted, so they are stable identifiers rather than
// display strings - renaming a label must never reset someone's choice.
// unlike LibrarySort this has no direction, just a cadence, because metadata
// does not change often enough to justify anything finer than weeks
enum MetadataRefreshInterval: String, CaseIterable, Identifiable {
    case off
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .weekly: "Week"
        case .biweekly: "Every 2 Weeks"
        case .monthly: "Month"
        }
    }

    // nil for .off, matching the same "no floor" absence
    // Constants.Refresh.automaticInterval's sibling would use. weekly and
    // biweekly are exact; monthly is a 30-day approximation rather than
    // calendar month math, which is close enough at this cadence
    var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .weekly: 7 * 24 * 60 * 60
        case .biweekly: 14 * 24 * 60 * 60
        case .monthly: 30 * 24 * 60 * 60
        }
    }
}

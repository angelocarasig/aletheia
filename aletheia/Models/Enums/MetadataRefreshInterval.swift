//
//  MetadataRefreshInterval.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// raw values are persisted, stable identifiers - renaming a case's raw
// value must never reset someone's choice
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

    // monthly is a deliberate 30-day approximation, not calendar month math -
    // close enough at this cadence
    var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .weekly: 7 * 24 * 60 * 60
        case .biweekly: 14 * 24 * 60 * 60
        case .monthly: 30 * 24 * 60 * 60
        }
    }
}

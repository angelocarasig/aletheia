//
//  SkipRecentInterval.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Foundation

// raw values are persisted, stable identifiers - renaming a case's raw
// value must never reset someone's choice
enum SkipRecentInterval: String, CaseIterable, Identifiable {
    case off
    case oneDay
    case threeDays
    case week
    case twoWeeks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .oneDay: "1 Day"
        case .threeDays: "3 Days"
        case .week: "1 Week"
        case .twoWeeks: "2 Weeks"
        }
    }

    var days: Int? {
        switch self {
        case .off: nil
        case .oneDay: 1
        case .threeDays: 3
        case .week: 7
        case .twoWeeks: 14
        }
    }
}

//
//  StatRange.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

// the raw values are persisted, so they are stable identifiers rather than
// display strings - renaming a label must never reset someone's choice
enum StatRange: String, CaseIterable, Identifiable {
    case week
    case month
    case halfYear
    case year
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "7 Days"
        case .month: "30 Days"
        case .halfYear: "6 Months"
        case .year: "1 Year"
        case .all: "All Time"
        }
    }

    // the earliest day the range counts, as a day key. day-bucketed and
    // inclusive of today, so 7 Days is seven columns rather than eight. all-time
    // has no floor and 0 sits below every real key, which keeps one query shape
    func sinceKey(from date: Date) -> Int {
        let calendar = Calendar.current
        let start: Date? = switch self {
        case .week: calendar.date(byAdding: .day, value: -6, to: date)
        case .month: calendar.date(byAdding: .day, value: -29, to: date)
        case .halfYear: calendar.date(byAdding: .month, value: -6, to: date)
        case .year: calendar.date(byAdding: .year, value: -1, to: date)
        case .all: nil
        }
        return start?.localDayKey ?? 0
    }
}

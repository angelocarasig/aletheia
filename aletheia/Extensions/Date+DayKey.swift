//
//  Date+DayKey.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

extension Date {
    // day identity fixed at write time - query-time 'localtime' bucketing is
    // unindexable and shifts under timezone travel; see docs/features/activity-history.md
    var localDayKey: Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}

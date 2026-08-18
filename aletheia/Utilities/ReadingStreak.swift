//
//  ReadingStreak.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

// runs of consecutive reading days, walked over localDayKey sets in swift -
// sql returns only the sparse days, the app owns the calendar. day identity,
// never elapsed seconds: dst gives 23- and 25-hour days and a seconds-based
// run breaks on both
enum ReadingStreak {
    // consecutive days ending today - or yesterday, so a run is not reported
    // broken before today has had a chance to happen
    static func current(days: Set<Int>, asOf: Date) -> Int {
        let calendar = Calendar.current
        var date = asOf

        if !days.contains(date.localDayKey) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
                days.contains(yesterday.localDayKey)
            else { return 0 }
            date = yesterday
        }

        var run = 0
        while days.contains(date.localDayKey) {
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return run
    }

    static func longest(days: Set<Int>) -> Int {
        let calendar = Calendar.current
        let dates = days.compactMap(date(from:)).sorted()

        var longest = 0
        var run = 0
        var previous: Date?

        for date in dates {
            if let previous,
                let expected = calendar.date(byAdding: .day, value: 1, to: previous),
                calendar.isDate(expected, inSameDayAs: date)
            {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = date
        }
        return longest
    }

    static func date(from key: Int) -> Date? {
        Calendar.current.date(
            from: DateComponents(
                year: key / 10_000,
                month: (key / 100) % 100,
                day: key % 100
            ))
    }
}

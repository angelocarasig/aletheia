//
//  UpdateBuckets.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Foundation

// buckets raw chapter publish dates into a contiguous 7-day window, zero-filled
// for days with no activity - mirrors ReadingBuckets' local-calendar-day
// reasoning rather than grouping by day in SQL
enum UpdateBuckets {
    struct Bucket: Identifiable, Hashable, Sendable {
        let start: Date
        let count: Int

        var id: Date { start }
    }

    static func week(_ dates: [Date], ending day: Date = .now, calendar: Calendar = .current)
        -> [Bucket]
    {
        let today = calendar.startOfDay(for: day)
        let days =
            (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .reversed()

        return days.map { start in
            let count = dates.filter { calendar.isDate($0, inSameDayAs: start) }.count
            return Bucket(start: start, count: count)
        }
    }
}

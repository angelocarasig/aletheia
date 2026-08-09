//
//  ReadingFormat.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

// how a duration and a day identity read, in one place. Home, the stats
// drill-down and the activity feed all state the same numbers, so the wording
// cannot be allowed to differ by which screen you reached them from
enum ReadingFormat {
    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }

    static func dayLabel(for key: Int) -> String {
        guard let date = ReadingStreak.date(from: key) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

//
//  ReadingFormat.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

// Home, the stats drill-down and the activity feed all state the same
// numbers, so the wording cannot be allowed to differ by screen
enum ReadingFormat {
    static func duration(_ seconds: Int) -> String {
        // a sitting under a minute is not zero - "0m" beside "49 pages" reads
        // as broken tracking, not a rounding floor. shown testers, every one
        // concluded the other numbers were suspect too
        guard seconds >= 60 else { return "\(max(0, seconds))s" }

        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }

    // a trailing .0 on every row reads as a rendering bug
    static func chapter(_ number: Double) -> String {
        let rounded = number.rounded()
        let value =
            abs(number - rounded) < 0.001
            ? String(Int(rounded))
            : String(format: "%g", number)
        return "Chapter \(value)"
    }

    static func dayLabel(for key: Int) -> String {
        guard let date = ReadingStreak.date(from: key) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

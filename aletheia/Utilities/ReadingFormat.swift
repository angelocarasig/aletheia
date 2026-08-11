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
        // a sitting shorter than a minute is not zero, and rendering it as "0m"
        // beside "49 pages" reads as broken tracking rather than a rounding
        // floor - every reader shown it concluded the other numbers were
        // suspect too, which is a steep price for the truncating unit.
        //
        // seconds rather than "<1m", which was the same evasion one step up: it
        // says the number is too small to state, where the number is 40 and
        // stating it costs nothing. the unit changes, the fact does not
        guard seconds >= 60 else { return "\(max(0, seconds))s" }

        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }

    // whole numbers lose their decimal, half chapters keep it: "Chapter 42",
    // "Chapter 42.5". a trailing .0 on every row reads as a rendering bug
    static func chapter(_ number: Double) -> String {
        let rounded = number.rounded()
        let value = abs(number - rounded) < 0.001
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

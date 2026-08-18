//
//  ReadingBuckets.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import SwiftUI

// sittings into fixed time buckets - twenty-four hours of a day, or seven days
// of a week - so a chart can ask "when do I read" rather than only "did I".
//
// THE REASON THIS IS NOT A GROUP BY: a session is an interval, not an instant.
// `localDayKey` is stamped from endedDate, so a sitting running 23:30 -> 00:30
// is filed wholly on the second day. A heatmap cell never noticed - it is on or
// off - but the moment a bar encodes a quantity, an hour of reading vanishes
// from one day and reappears in the next, and in an hourly chart it lands at
// 00:00 when half of it was 23:00. Buckets are therefore computed by INTERVAL
// INTERSECTION here in Swift, which is also where docs/features/metrics.md
// puts calendar and presentation maths.
// what a bar's height and a grid cell's intensity mean. one choice drives both,
// because the two are one layer of information and a grid measuring chapters
// beside bars measuring pages is a palette claiming a consistency it lacks
enum ReadingMetric: String, CaseIterable, Identifiable, Sendable {
    case pages
    case chapters

    var id: Self { self }

    var label: String {
        switch self {
        case .pages: "Pages"
        case .chapters: "Chapters"
        }
    }

    var caption: String {
        switch self {
        case .pages: "Pages read per day"
        case .chapters: "Chapters finished per day"
        }
    }
}

enum ReadingBuckets {
    struct Bucket: Identifiable, Hashable, Sendable {
        let start: Date
        let pages: Int
        let chapters: Int
        let seconds: Int

        var id: Date { start }
        var isEmpty: Bool { pages == 0 && chapters == 0 && seconds == 0 }

        func value(_ metric: ReadingMetric) -> Int {
            switch metric {
            case .pages: pages
            case .chapters: chapters
            }
        }
    }

    // pages are counted per sitting rather than per instant, so a sitting that
    // straddles a boundary has its pages apportioned by how much of its elapsed
    // time fell either side. that assumes an even pace, which is untrue in
    // detail and honest in aggregate - the alternative, filing the whole sitting
    // under the bucket it began in, states that a two-hour read happened
    // entirely at 21:00
    static func hourly(
        _ sessions: [ReadingSessionEntry],
        on day: Date,
        calendar: Calendar = .current
    ) -> [Bucket] {
        guard let dayStart = calendar.dateInterval(of: .day, for: day)?.start else { return [] }

        let starts = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
        return distribute(
            sessions, into: starts, next: { calendar.date(byAdding: .hour, value: 1, to: $0) })
    }

    static func daily(
        _ sessions: [ReadingSessionEntry],
        weekOf day: Date,
        calendar: Calendar = .current
    ) -> [Bucket] {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start else {
            return []
        }

        let starts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        return distribute(
            sessions, into: starts, next: { calendar.date(byAdding: .day, value: 1, to: $0) })
    }

    // the average ACTIVE bucket across everything handed in, at the same
    // granularity the chart is drawing. empty buckets are excluded on purpose:
    // a mean over every hour of every day is a number no hour ever looked like,
    // and the question the line answers is "what does a bar of mine usually
    // look like", not "what is my rate around the clock".
    //
    // walks each sitting into only the buckets it actually touches rather than
    // against a fixed spine, so the cost is the number of sittings and not the
    // length of history
    static func averageActive(
        _ sessions: [ReadingSessionEntry],
        of granularity: Calendar.Component,
        metric: ReadingMetric,
        calendar: Calendar = .current
    ) -> Int? {
        var totals: [Date: Double] = [:]

        for session in sessions {
            let span = session.endedDate.timeIntervalSince(session.startedDate)
            let amount = Double(metric == .pages ? session.pagesRead : session.chaptersRead)
            guard amount > 0 else { continue }

            guard span > 0 else {
                if let start = calendar.dateInterval(of: granularity, for: session.startedDate)?
                    .start
                {
                    totals[start, default: 0] += amount
                }
                continue
            }

            var cursor = session.startedDate
            while cursor < session.endedDate {
                guard let interval = calendar.dateInterval(of: granularity, for: cursor) else {
                    break
                }
                let overlap = min(session.endedDate, interval.end).timeIntervalSince(
                    max(session.startedDate, interval.start))
                if overlap > 0 { totals[interval.start, default: 0] += amount * overlap / span }
                cursor = interval.end
            }
        }

        let active = totals.values.filter { $0 >= 0.5 }
        guard !active.isEmpty else { return nil }
        return Int((active.reduce(0, +) / Double(active.count)).rounded())
    }

    // every sitting the bucket overlaps, in the order handed in. membership
    // follows the bars rather than the stored localDayKey: a sitting running
    // 23:40 -> 00:20 built both bars, so tapping either has to find it, and
    // filing it by start alone leaves the second bar with height and nothing
    // behind it. the rows keep their own whole values - the bucket's share is
    // the bar's business, not the sitting's
    static func sittings(
        _ sessions: [ReadingSessionEntry],
        in bucket: Bucket,
        of granularity: Calendar.Component,
        calendar: Calendar = .current
    ) -> [ReadingSessionEntry] {
        guard let interval = calendar.dateInterval(of: granularity, for: bucket.start) else {
            return []
        }

        return sessions.filter { session in
            guard session.endedDate > session.startedDate else {
                return session.startedDate >= interval.start && session.startedDate < interval.end
            }
            // half-open on both sides: DateInterval.contains includes its end,
            // which puts a sitting starting exactly at 14:00 in the 13:00 bucket
            return session.startedDate < interval.end && session.endedDate > interval.start
        }
    }

    private static func distribute(
        _ sessions: [ReadingSessionEntry],
        into starts: [Date],
        next: (Date) -> Date?
    ) -> [Bucket] {
        var pages = [Int](repeating: 0, count: starts.count)
        var chapters = [Int](repeating: 0, count: starts.count)
        var seconds = [Int](repeating: 0, count: starts.count)

        for session in sessions {
            let span = session.endedDate.timeIntervalSince(session.startedDate)

            for (index, bucketStart) in starts.enumerated() {
                guard let bucketEnd = next(bucketStart) else { continue }

                let from = max(session.startedDate, bucketStart)
                let to = min(session.endedDate, bucketEnd)

                // a sitting recorded as instantaneous still happened somewhere,
                // so it lands whole in the bucket containing its start rather
                // than dividing by a zero span
                guard span > 0 else {
                    if session.startedDate >= bucketStart, session.startedDate < bucketEnd {
                        pages[index] += session.pagesRead
                        chapters[index] += session.chaptersRead
                    }
                    continue
                }

                let overlap = to.timeIntervalSince(from)
                guard overlap > 0 else { continue }

                seconds[index] += Int(overlap.rounded())
                pages[index] += Int((Double(session.pagesRead) * overlap / span).rounded())
                chapters[index] += Int((Double(session.chaptersRead) * overlap / span).rounded())
            }
        }

        return starts.indices.map {
            Bucket(
                start: starts[$0], pages: pages[$0], chapters: chapters[$0], seconds: seconds[$0])
        }
    }
}

#if DEBUG
    extension ReadingBuckets {
        // the boundary cases the interval maths exists for. run from a preview or a
        // scratch target; assertions rather than a test file, since the project has
        // no test target
        static func check() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!

            func session(from: Date, to: Date, pages: Int) -> ReadingSessionEntry {
                ReadingSessionEntry(
                    id: 1,
                    seriesId: 1,
                    seriesTitle: "",
                    pagesRead: pages,
                    chaptersRead: 0,
                    startedDate: from,
                    endedDate: to,
                    localDayKey: to.localDayKey,
                    alive: true,
                    cover: nil,
                    path: nil
                )
            }

            let midnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
            let straddle = session(
                from: midnight.addingTimeInterval(-1_800),
                to: midnight.addingTimeInterval(1_800),
                pages: 40
            )

            // half the sitting fell before midnight, so half the pages did too -
            // the stored localDayKey would have filed all forty on the tenth
            let hours = hourly([straddle], on: midnight, calendar: calendar)
            assert(hours.count == 24)
            assert(
                hours[0].pages == 20,
                "expected half of a midnight straddle in hour 0, got \(hours[0].pages)")
            assert(hours[1...].allSatisfy { $0.pages == 0 })

            // an instantaneous sitting divides by no span and still lands somewhere
            let instant = midnight.addingTimeInterval(3_600 * 9)
            let zero = hourly(
                [session(from: instant, to: instant, pages: 12)], on: midnight, calendar: calendar)
            assert(zero[9].pages == 12, "expected an instant sitting whole in its own hour")
            assert(
                zero.reduce(0) { $0 + $1.pages } == 12,
                "an instant sitting must not be counted twice")

            // the straddle built two bars, so both have to be able to name it - and
            // a bucket it never touched must not
            let before = hourly(
                [straddle], on: midnight.addingTimeInterval(-3_600), calendar: calendar)
            assert(sittings([straddle], in: hours[0], of: .hour, calendar: calendar).count == 1)
            assert(
                sittings([straddle], in: before[23], of: .hour, calendar: calendar).count == 1,
                "a sitting crossing midnight must appear under the hour it started in")
            assert(sittings([straddle], in: hours[5], of: .hour, calendar: calendar).isEmpty)

            // a sitting ending exactly on a boundary belongs to the bucket it was
            // in, not the one it stopped at
            let upTo = session(from: midnight, to: midnight.addingTimeInterval(3_600), pages: 5)
            assert(sittings([upTo], in: hours[0], of: .hour, calendar: calendar).count == 1)
            assert(sittings([upTo], in: hours[1], of: .hour, calendar: calendar).isEmpty)

            // a week bucket set is seven long and conserves what it was given
            let week = daily([straddle], weekOf: midnight, calendar: calendar)
            assert(week.count == 7)
            assert(week.reduce(0) { $0 + $1.pages } <= 40)

            AppLog.shared.log("reading buckets ok", level: .debug, category: "stats")
        }
    }

    // the interval maths is the one part of this feature that can be silently wrong
    // and look right, so it gets the check. run the preview: it traps on failure and
    // prints otherwise
    #Preview("Bucket check") {
        let _ = ReadingBuckets.check()

        return Text("buckets ok")
            .font(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.canvas)
    }
#endif

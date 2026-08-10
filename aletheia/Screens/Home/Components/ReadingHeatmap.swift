//
//  ReadingHeatmap.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

// a contribution-style record of reading days: columns are weeks, rows are
// weekdays, intensity is chapters finished. a passive record, never a
// countdown.
//
// THE RULE THIS GRID BROKE AND NOW KEEPS: an unlabelled contributions grid is
// decoration. Without a stated metric a reader cannot say what the colour means,
// and without axes they cannot say when a cell is - so the whole chart encodes
// nothing recoverable. Everyone shown the unlabelled version guessed "one square
// is a day" from the row count alone, and one read the empty left gutter as a
// rendering fault. The weekday stubs are what that gutter is for.
struct ReadingHeatmap: View {
    let heat: [Int: Int]
    let weeks: Int
    let asOf: Date
    // the span the chart above is currently showing. the two are one layer of
    // information at two resolutions, so the grid outlines the days the bars
    // are made of rather than sitting beside them as a second opinion
    var highlight: DateInterval?
    var metric: ReadingMetric = .pages
    // the grid is the index and the chart below is the detail, so a cell is a
    // way in rather than a swatch. asserting the link with a marker never
    // worked - demonstrating it does
    var onSelect: ((Date) -> Void)?

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Namespace private var marker

    private enum Layout {
        static let cell: CGFloat = 14
        static let spacing: CGFloat = 3
        static let stubWidth: CGFloat = 26
        static let monthHeight: CGFloat = 14
        // an abbreviated month needs roughly this many columns of room to its
        // right before it starts running off the end of the grid
        static let monthClearance = 3
        // the empty tone is neutral, never the ramp's zeroth step: brand at a
        // low opacity against near-black is about one just-noticeable
        // difference on a dim OLED, so "did not read" and "read a little" would
        // be the same colour to most eyes in most rooms
        // both channels, not either. dimming alone was too quiet to find - the
        // eye has nothing to catch on - and the earlier green ring alone read as
        // a per-cell verdict. together the outline says "here" and the dimming
        // says "not there", and the outline is drawn in the text colour rather
        // than a semantic one so it cannot be mistaken for a status
        static let dimmed: Double = 0.3
        static let markWidth: CGFloat = 1.5
        static let markOpacity: Double = 0.85
        static let markerID = "period"
        // a day with no reading still has to read as a cell rather than as a
        // hole in the grid - too far down and the whole shape disappears into
        // the background and only the filled days look like anything at all
        static let emptyOpacity = 0.22
        static let lowOpacity = 0.45
        static let midOpacity = 0.62
        // quantiles of the days actually read, not fractions of the busiest one.
        // peak-derived thresholds let a single enormous day push every ordinary
        // day into the lowest bin, and on a short record they produced "one day,
        // top bin, 270+" - noise rendered as achievement.
        //
        // below a real sample there is nothing to take a quantile of, so the
        // scale falls back to absolute page counts. self-referential is right in
        // principle; self-referential to n=1 is not
        static let sampleMinimum = 14
        static let absoluteLow = 20
        static let absoluteMid = 60
    }

    private var calendar: Calendar { Calendar.current }

    // half-open, written out rather than DateInterval.contains - that one is
    // inclusive of `end`, so a day period matched its own midnight AND the next
    // day's, and a week matched eight columns
    private func inPeriod(_ date: Date) -> Bool {
        guard let highlight else { return true }
        return date >= highlight.start && date < highlight.end
    }

    private var active: [Int] { heat.values.filter { $0 > 0 }.sorted() }

    private var peak: Int { active.last ?? 0 }

    private var lowCap: Int {
        active.count >= Layout.sampleMinimum ? quantile(0.5) : Layout.absoluteLow
    }

    private var midCap: Int {
        active.count >= Layout.sampleMinimum ? quantile(0.8) : Layout.absoluteMid
    }

    private func quantile(_ fraction: Double) -> Int {
        guard !active.isEmpty else { return 0 }
        let index = min(active.count - 1, Int((Double(active.count - 1) * fraction).rounded()))
        return max(1, active[index])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            // the grid cannot say what its own colour measures, so the caption
            // does. without it the legend reads "more of what?"
            Text(metric.caption)
                .font(.caption2)
                .foregroundStyle(.muted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Layout.spacing) {
                    Stubs

                    ForEach(0..<weeks, id: \.self) { week in
                        WeekColumn(week)
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reading activity over the last \(weeks) weeks")

            Legend
        }
        // a spring rather than .settle: .settle is the crossfade curve for a
        // load swapping in, and this is a thing travelling a measurable distance
        .animation(.snappy(duration: 0.28), value: highlight)
    }

    // Mon/Wed/Fri only - every row labelled is a wall of text at this cell size,
    // and three anchors are enough to count from
    // hidden rather than shrunk once text scales: 9pt was below the platform's
    // legibility floor, and a label that cannot survive scaling has to be
    // removable instead. the stubs are the most redundant thing here - the row
    // order is a week, which the month ruler above already anchors
    @ViewBuilder
    private var Stubs: some View {
        if dynamicTypeSize < .accessibility1 {
            VStack(spacing: Layout.spacing) {
                Color.clear
                    .frame(height: Layout.monthHeight)

                ForEach(0..<7, id: \.self) { day in
                    Text(day.isMultiple(of: 2) ? "" : weekday(day))
                        .font(.caption2)
                        .foregroundStyle(.muted)
                        .frame(width: Layout.stubWidth, height: Layout.cell, alignment: .leading)
                }
            }
        }
    }

    private func WeekColumn(_ week: Int) -> some View {
        VStack(spacing: Layout.spacing) {
            // a month name sits over the first column that falls inside it, so
            // the ruler appears where the month actually turns
            // never clipped to one cell: a month name is wider than a 14pt
            // square, so constraining it produced "J..." and "A...". it is
            // anchored at its first column and allowed to overflow rightward,
            // and it is dropped entirely when too few columns remain to carry it
            Text(monthLabel(week))
                .font(.caption2)
                .foregroundStyle(.muted)
                .fixedSize()
                .frame(width: Layout.cell, height: Layout.monthHeight, alignment: .leading)
                .zIndex(1)

            ForEach(0..<7, id: \.self) { day in
                Cell(for: date(week: week, day: day))
            }
        }
        // ONE marker, not an outline per cell. a week in this grid is a column
        // and a day is a cell inside it, so every selection is a contiguous
        // vertical run in a single column - which means the marker can be a
        // single rectangle that travels and resizes between them rather than
        // one set fading out while another fades in.
        //
        // fading said "that selection ended, this one began". moving says "the
        // selection you are holding went there", which is what the chevron did
        .overlay(alignment: .top) {
            if let run = markedRun(week) {
                RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                    .strokeBorder(.primary.opacity(Layout.markOpacity), lineWidth: Layout.markWidth)
                    .frame(width: Layout.cell, height: height(of: run.count))
                    .offset(y: offset(to: run.start))
                    .matchedGeometryEffect(id: Layout.markerID, in: marker)
            }
        }
    }

    // the contiguous stretch of this column that falls inside the period, as a
    // start row and a length. nil when the column is untouched by it
    private func markedRun(_ week: Int) -> (start: Int, count: Int)? {
        let marked = (0..<7).filter { day in
            guard let date = date(week: week, day: day) else { return false }
            return inPeriod(date)
        }
        guard let first = marked.first, let last = marked.last else { return nil }
        return (first, last - first + 1)
    }

    private func height(of rows: Int) -> CGFloat {
        CGFloat(rows) * Layout.cell + CGFloat(rows - 1) * Layout.spacing
    }

    private func offset(to row: Int) -> CGFloat {
        Layout.monthHeight + Layout.spacing + CGFloat(row) * (Layout.cell + Layout.spacing)
    }

    @ViewBuilder
    private func Cell(for date: Date?) -> some View {
        if let date, date <= asOf {
            RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                .fill(fill(for: heat[date.localDayKey] ?? 0))
                .frame(width: Layout.cell, height: Layout.cell)
                .opacity(inPeriod(date) ? 1 : Layout.dimmed)
                .contentShape(.rect)
                .tappable { onSelect?(date) }
        } else {
            // a day that has not happened yet holds its place invisibly, so
            // the current week's column keeps the grid's shape
            Color.clear
                .frame(width: Layout.cell, height: Layout.cell)
        }
    }

    private var Legend: some View {
        HStack(spacing: dimensions.spacing.space4) {
            Text("None")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach([0, lowCap, midCap, midCap + 1], id: \.self) { count in
                RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                    .fill(fill(for: count))
                    .frame(width: Layout.cell, height: Layout.cell)
            }

            // the reader's own busiest day, which is the only number on this
            // ramp that is a ceiling. printing the middle threshold instead
            // named an interior boundary as if it were the top, and read as a
            // target set by somebody else
            Text(peak > 0 ? "\(peak)" : "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func fill(for count: Int) -> AnyShapeStyle {
        switch count {
        case 0: AnyShapeStyle(Palette.muted.opacity(Layout.emptyOpacity))
        case ...lowCap: AnyShapeStyle(Palette.brand.opacity(Layout.lowOpacity))
        case ...midCap: AnyShapeStyle(Palette.brand.opacity(Layout.midOpacity))
        default: AnyShapeStyle(Palette.brand)
        }
    }

    private func weekday(_ day: Int) -> String {
        guard let date = date(week: weeks - 1, day: day) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    // anchored from the newest column and walked backwards, so the month you
    // are actually in always gets a label. walking forwards dropped it whenever
    // the current month was younger than the clearance - which is most of the
    // time, and is why a grid ending in August was labelled only to July
    private var monthColumns: Set<Int> {
        var labelled: Set<Int> = []
        var last: Int?

        for week in stride(from: weeks - 1, through: 0, by: -1) {
            guard let current = date(week: week, day: 0) else { continue }
            guard let previous = date(week: week - 1, day: 0),
                  !calendar.isDate(current, equalTo: previous, toGranularity: .month)
            else {
                if week == weeks - 1, last == nil { labelled.insert(week); last = week }
                continue
            }

            // never two labels close enough to collide, since a month name is
            // wider than the cell it is anchored to
            if let last, last - week < Layout.monthClearance { continue }
            labelled.insert(week)
            last = week
        }

        return labelled
    }

    private func monthLabel(_ week: Int) -> String {
        guard monthColumns.contains(week), let current = date(week: week, day: 0) else { return "" }
        return current.formatted(.dateTime.month(.abbreviated))
    }

    // week 0 is the oldest column; day 0 is the first weekday of the user's
    // calendar. dates come from the calendar, never from key arithmetic
    private func date(week: Int, day: Int) -> Date? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: asOf)?.start,
              let weekStart = calendar.date(byAdding: .weekOfYear, value: week - (weeks - 1), to: thisWeek)
        else { return nil }
        return calendar.date(byAdding: .day, value: day, to: weekStart)
    }
}

// MARK: - Previews

#Preview("Populated") {
    ReadingHeatmap(
        heat: {
            var heat: [Int: Int] = [:]
            let calendar = Calendar.current
            for offset in stride(from: 0, to: 90, by: 2) {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
                heat[date.localDayKey] = offset % 5
            }
            return heat
        }(),
        weeks: 16,
        asOf: .now
    )
    .padding()
    .background(.canvas)
}

// the bins, one per row, so the empty tone can be checked against the lowest
// filled one - the pair the old ramp could not separate
#Preview("Bins") {
    ReadingHeatmap(
        heat: {
            var heat: [Int: Int] = [:]
            let calendar = Calendar.current
            for (offset, count) in [(0, 8), (1, 3), (2, 1), (3, 0), (7, 12), (8, 2)] {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
                heat[date.localDayKey] = count
            }
            return heat
        }(),
        weeks: 16,
        asOf: .now
    )
    .padding()
    .background(.canvas)
}

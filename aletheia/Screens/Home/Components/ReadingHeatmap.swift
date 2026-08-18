//
//  ReadingHeatmap.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

// unlabelled, this grid tested as decoration - readers guessed the metric from
// row count alone, and one read the empty left gutter as a rendering fault.
// the weekday stubs are what that gutter is for
struct ReadingHeatmap: View {
    let heat: [Int: Int]
    let weeks: Int
    let asOf: Date
    var highlight: DateInterval?
    var metric: ReadingMetric = .pages
    var onSelect: ((Date) -> Void)?

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Namespace private var marker

    private enum Layout {
        static let cell: CGFloat = 14
        static let spacing: CGFloat = 3
        static let stubWidth: CGFloat = 26
        static let monthHeight: CGFloat = 14
        static let monthClearance = 3
        // dim + outline together, not opacity alone - too subtle to notice; an
        // earlier ring-only design read as a per-cell verdict, not a highlight
        static let dimmed: Double = 0.3
        static let markWidth: CGFloat = 1.5
        static let markOpacity: Double = 0.85
        static let markerID = "period"
        // brand at low opacity is near-indistinguishable from itself on a dim
        // OLED, so zero uses a separate neutral tone rather than the ramp's
        // own lowest step
        static let emptyOpacity = 0.22
        static let lowOpacity = 0.45
        static let midOpacity = 0.62
        // quantiles of days actually read, not fractions of the peak - a
        // peak-derived scale let one huge day push every other into the lowest
        // bin. below a real sample there's nothing to take a quantile of, so
        // this falls back to absolute counts
        static let sampleMinimum = 14
        static let absoluteLow = 20
        static let absoluteMid = 60
    }

    private var calendar: Calendar { Calendar.current }

    // half-open, written out rather than DateInterval.contains(_:) - that's
    // inclusive of `end`, which matched a day period against its own midnight
    // AND the next day's
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
        // .settle is the crossfade for a load swapping in; this marker travels a
        // measurable distance, which wants a spring instead
        .animation(.snappy(duration: 0.28), value: highlight)
    }

    // hidden rather than shrunk past a point: 9pt is below the platform's
    // legibility floor, so a label that can't survive scaling gets removed
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
            // not clipped to one cell - a month name is wider than 14pt and
            // constraining it produced "J..."/"A..."; this overflows rightward
            // from its anchor column instead
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
        // one marker that moves and resizes via matchedGeometryEffect, not a
        // fade-out/fade-in pair - a selection is always a contiguous run in
        // one column
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

    // walked backwards from the newest column - walking forwards dropped the
    // current month whenever it was younger than the clearance, which is most
    // of the time (a grid ending in August was labelled only to July)
    private var monthColumns: Set<Int> {
        var labelled: Set<Int> = []
        var last: Int?

        for week in stride(from: weeks - 1, through: 0, by: -1) {
            guard let current = date(week: week, day: 0) else { continue }
            guard let previous = date(week: week - 1, day: 0),
                !calendar.isDate(current, equalTo: previous, toGranularity: .month)
            else {
                if week == weeks - 1, last == nil {
                    labelled.insert(week)
                    last = week
                }
                continue
            }

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

    // always through Calendar, never fixed-interval offset math - DST shifts
    // break a raw 86400-second day/week stride
    private func date(week: Int, day: Int) -> Date? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: asOf)?.start,
            let weekStart = calendar.date(
                byAdding: .weekOfYear, value: week - (weeks - 1), to: thisWeek)
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
                guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else {
                    continue
                }
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

#Preview("Bins") {
    ReadingHeatmap(
        heat: {
            var heat: [Int: Int] = [:]
            let calendar = Calendar.current
            for (offset, count) in [(0, 8), (1, 3), (2, 1), (3, 0), (7, 12), (8, 2)] {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else {
                    continue
                }
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

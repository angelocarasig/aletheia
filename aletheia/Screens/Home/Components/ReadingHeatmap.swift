//
//  ReadingHeatmap.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

// a contribution-style record of reading days: columns are weeks, rows are
// weekdays, intensity is chapters finished. a passive record, never a
// countdown - the run tiles beside it state facts, this shows the shape
struct ReadingHeatmap: View {
    let heat: [Int: Int]
    let weeks: Int
    let asOf: Date

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let cell: CGFloat = 14
        static let spacing: CGFloat = 3
        static let emptyOpacity = 0.06
        static let lowOpacity = 0.3
        static let midOpacity = 0.55
        static let lowCap = 1
        static let midCap = 3
    }

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .trailing, spacing: dimensions.spacing.space8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Layout.spacing) {
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
    }

    private func WeekColumn(_ week: Int) -> some View {
        VStack(spacing: Layout.spacing) {
            ForEach(0..<7, id: \.self) { day in
                Cell(for: date(week: week, day: day))
            }
        }
    }

    @ViewBuilder
    private func Cell(for date: Date?) -> some View {
        if let date, date <= asOf {
            RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                .fill(fill(for: heat[date.localDayKey] ?? 0))
                .frame(width: Layout.cell, height: Layout.cell)
        } else {
            // a day that has not happened yet holds its place invisibly, so
            // the current week's column keeps the grid's shape
            Color.clear
                .frame(width: Layout.cell, height: Layout.cell)
        }
    }

    private var Legend: some View {
        HStack(spacing: dimensions.spacing.space4) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach([0, Layout.lowCap, Layout.midCap, Layout.midCap + 1], id: \.self) { count in
                RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                    .fill(fill(for: count))
                    .frame(width: Layout.cell, height: Layout.cell)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private func fill(for count: Int) -> AnyShapeStyle {
        switch count {
        case 0: AnyShapeStyle(.primary.opacity(Layout.emptyOpacity))
        case ...Layout.lowCap: AnyShapeStyle(Palette.brand.opacity(Layout.lowOpacity))
        case ...Layout.midCap: AnyShapeStyle(Palette.brand.opacity(Layout.midOpacity))
        default: AnyShapeStyle(Palette.brand)
        }
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

#Preview {
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
}

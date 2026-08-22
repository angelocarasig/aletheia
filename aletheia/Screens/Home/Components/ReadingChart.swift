//
//  ReadingChart.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Charts
import SwiftUI

struct ReadingChart: View {
    let sessions: [ReadingSessionEntry]
    @Binding var scope: Scope
    @Binding var metric: ReadingMetric
    @Binding var anchor: Date
    let asOf: Date
    let earliest: Date
    @Binding var selected: Date?

    @Environment(\.dimensions) private var dimensions
    @Environment(\.calendar) private var calendar

    enum Scope: String, CaseIterable, Identifiable {
        case day
        case week

        var id: Self { self }

        var label: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            }
        }
    }

    private enum Layout {
        static let chartHeight: CGFloat = 168
        // fixed regardless of selection so scrubbing never reflows the screen
        static let readoutHeight: CGFloat = 44
        static let dayBarWidth: CGFloat = 8
        static let weekBarWidth: CGFloat = 34
        static let radius: CGFloat = 4
        static let dayFloor = 40
        static let weekFloor = 200
        static let dayFloorChapters = 4
        static let weekFloorChapters = 12
        static let unselectedOpacity: Double = 0.4
        static let stepTarget: CGFloat = 44
        static let controlFill: Double = 0.06
        static let ruleGutter: CGFloat = 26
        static let stepDisabled: Double = 0.4
        static let keyWidth: CGFloat = 12
        static let keyHeight: CGFloat = 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Stepper

            Readout

            Chart

            Legend
        }
        .animation(.settle, value: scope)
        .animation(.settle, value: anchor)
        .animation(.settle, value: selected)
        .onChange(of: scope) {
            selected = nil
            anchor = asOf
        }
        .onChange(of: metric) { selected = nil }
        .sensoryFeedback(.selection, trigger: selectedBucket?.start)
    }

    // MARK: Period

    private var Stepper: some View {
        GlassEffectContainer(spacing: dimensions.spacing.space12) {
            HStack(spacing: dimensions.spacing.space12) {
                Step("chevron.left", enabled: canGoBack) { shift(by: -1) }

                Text(periodLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())

                Step("chevron.right", enabled: canGoForward) { shift(by: 1) }
            }
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .sensoryFeedback(.selection, trigger: anchor)
    }

    @ViewBuilder
    private func Step(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let icon = Image(systemName: glyph)
            .foregroundStyle(enabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.muted))
            .frame(width: Layout.stepTarget, height: Layout.stepTarget)

        // .disabled() alone doesn't read here - glass keeps its lensing at any
        // opacity, so the surface is removed entirely instead of dimmed
        if enabled {
            icon
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .tappable(action: action)
                .transition(.opacity)
        } else {
            icon
                .opacity(Layout.stepDisabled)
                .accessibilityHidden(true)
        }
    }

    private func shift(by amount: Int) {
        guard let moved = calendar.date(byAdding: component, value: amount, to: anchor) else {
            return
        }
        selected = nil
        anchor = moved
    }

    private var component: Calendar.Component { scope == .day ? .day : .weekOfYear }

    private var canGoBack: Bool {
        guard let previous = calendar.date(byAdding: component, value: -1, to: anchor),
            let target = calendar.dateInterval(of: component, for: previous)?.start,
            let floor = calendar.dateInterval(of: component, for: earliest)?.start
        else { return false }
        return target >= floor
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: component, value: 1, to: anchor),
            let target = calendar.dateInterval(of: component, for: next)?.start,
            let present = calendar.dateInterval(of: component, for: asOf)?.start
        else { return false }
        return target <= present
    }

    private var periodLabel: String {
        switch scope {
        case .day:
            if calendar.isDateInToday(anchor) { return "Today" }
            if calendar.isDateInYesterday(anchor) { return "Yesterday" }
            return anchor.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) else {
                return ""
            }
            if calendar.isDate(asOf, equalTo: anchor, toGranularity: .weekOfYear) {
                return "This Week"
            }
            let end = interval.end.addingTimeInterval(-1)
            return
                "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) - \(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }

    // MARK: Readout

    private var Readout: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Headline
                    .font(.title2)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())

                Detail
                    .font(.caption)
                    .foregroundStyle(.muted)
            }

            Spacer(minLength: dimensions.spacing.space12)

            Menu {
                Picker("Metric", selection: $metric) {
                    ForEach(ReadingMetric.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                HStack(spacing: dimensions.spacing.space4) {
                    Text(metric.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, dimensions.spacing.space12)
                .padding(.vertical, dimensions.spacing.space8)
                .background(.primary.opacity(Layout.controlFill), in: .capsule)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Metric")
            .accessibilityValue(metric.label)
        }
        .frame(height: Layout.readoutHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.settle, value: selectedBucket)
    }

    // always the period total, never the selected bucket - a version that
    // switched meaning under "Today" read as broken math
    private var Headline: some View {
        Amount(total)
    }

    // branches, not a String - inflection markup ("^[n page](inflect: true)")
    // silently renders literally if it passes through a String or ternary
    // instead of reaching Text directly; this shipped that bug, see design.md §13
    @ViewBuilder
    private func Amount(_ count: Int) -> some View {
        switch metric {
        case .pages: Text("^[\(count) page](inflect: true)")
        case .chapters: Text("^[\(count) chapter](inflect: true)")
        }
    }

    private var Detail: some View {
        WindowDetail
    }

    @ViewBuilder
    private var WindowDetail: some View {
        let before = previous.reduce(0) { $0 + $1.value(metric) }

        if before > 0 {
            HStack(spacing: dimensions.spacing.space4) {
                Text(total >= before ? "up from" : "down from")
                Amount(before)
                Text("last \(previousName)")
            }
        } else if total > 0 {
            EmptyView()
        } else {
            Text("No reading")
        }
    }

    private var total: Int { buckets.reduce(0) { $0 + $1.value(metric) } }

    private var previousName: String { scope == .day ? "day" : "week" }

    private func bucketLabel(_ bucket: ReadingBuckets.Bucket) -> String {
        switch scope {
        case .day: bucket.start.formatted(.dateTime.hour())
        case .week: bucket.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }

    @ViewBuilder
    private var Legend: some View {
        if periodAverage != nil || lifetimeAverage != nil {
            VStack(spacing: dimensions.spacing.space4) {
                if periodAverage != nil {
                    Key(
                        colour: Palette.success,
                        label: scope == .day ? "Daily Average" : "Weekly Average")
                }

                if lifetimeAverage != nil {
                    Key(colour: Palette.warning, label: "All-Time Average")
                }
            }
            .font(.caption)
        }
    }

    private func Key(colour: Color, label: String) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Capsule()
                .fill(colour)
                .frame(width: Layout.keyWidth, height: Layout.keyHeight)

            Text(label)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private func RuleValue(_ value: Int, colour: Color) -> some View {
        Text("\(value)")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(colour)
            .contentTransition(.numericText())
    }

    // MARK: Chart

    private var Chart: some View {
        Charts.Chart {
            ForEach(buckets) { bucket in
                if bucket.value(metric) > 0 {
                    BarMark(
                        x: .value("When", bucket.start, unit: unit),
                        y: .value(metric.label, bucket.value(metric)),
                        width: .fixed(barWidth)
                    )
                    .clipShape(.rect(cornerRadius: Layout.radius))
                    .foregroundStyle(Palette.brand)
                    .opacity(
                        highlighted == nil || selectedBucket?.id == bucket.id
                            ? 1 : Layout.unselectedOpacity
                    )
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        if selectedBucket?.id == bucket.id {
                            VStack(spacing: 0) {
                                Amount(bucket.value(metric))
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                Text(bucketLabel(bucket))
                                    .font(.caption2)
                                    .foregroundStyle(.muted)
                            }
                            .padding(.horizontal, dimensions.spacing.space8)
                            .padding(.vertical, dimensions.spacing.space4)
                            .background(
                                .regularMaterial, in: .rect(cornerRadius: dimensions.radius.radius8)
                            )
                        }
                    }
                }
            }

            if let periodAverage {
                RuleMark(y: .value("Average", periodAverage))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .foregroundStyle(Palette.success)
                    .annotation(
                        position: .trailing, alignment: .center, spacing: dimensions.spacing.space4
                    ) {
                        RuleValue(periodAverage, colour: Palette.success)
                    }
            }

            if let lifetimeAverage {
                RuleMark(y: .value("All-time average", lifetimeAverage))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    .foregroundStyle(Palette.warning)
                    .annotation(
                        position: .trailing, alignment: .center, spacing: dimensions.spacing.space4
                    ) {
                        RuleValue(lifetimeAverage, colour: Palette.warning)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...ceiling)
        .chartXSelection(value: selection)
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, ceiling / 2, ceiling]) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisValueLabel(centered: scope == .week) {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date))
                            .font(.caption2)
                            .foregroundStyle(
                                isToday(date) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.muted))
                    }
                }
            }
        }
        .frame(height: Layout.chartHeight)
        // rule value annotations render outside the plot bounds and clip
        // against the screen edge without this
        .padding(.trailing, Layout.ruleGutter)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .overlay {
            if buckets.allSatisfy(\.isEmpty) {
                Text("No reading")
                    .font(.subheadline)
                    .foregroundStyle(.muted)
            }
        }
    }

    // MARK: Data

    private var buckets: [ReadingBuckets.Bucket] {
        switch scope {
        case .day: ReadingBuckets.hourly(sessions, on: anchor, calendar: calendar)
        case .week: ReadingBuckets.daily(sessions, weekOf: anchor, calendar: calendar)
        }
    }

    private var previous: [ReadingBuckets.Bucket] {
        switch scope {
        case .day:
            guard let day = calendar.date(byAdding: .day, value: -1, to: anchor) else { return [] }
            return ReadingBuckets.hourly(sessions, on: day, calendar: calendar)
        case .week:
            guard let week = calendar.date(byAdding: .weekOfYear, value: -1, to: anchor) else {
                return []
            }
            return ReadingBuckets.daily(sessions, weekOf: week, calendar: calendar)
        }
    }

    // week scope has no "nothing highlighted" state - anchor always points to
    // some day, and that day's bar is what's highlighted, tap or not. day
    // scope keeps the old on/off behaviour: nothing is highlighted until an
    // hour is tapped, and tapping it again clears it
    private var highlighted: Date? {
        switch scope {
        case .day: selected
        case .week: calendar.dateInterval(of: .day, for: anchor)?.start
        }
    }

    private var selectedBucket: ReadingBuckets.Bucket? {
        guard let highlighted else { return nil }
        return buckets.last { $0.start <= highlighted }
    }

    // selectXValue reports wherever the finger landed, not a bucket boundary -
    // two taps on the same bar produce different near-identical dates, so
    // comparing raw values would never toggle. snap to bucket.start first.
    // a week-scope tap moves anchor itself (the day being viewed), not a
    // separate selection - the same "tap = jump to that day" rule the
    // heatmap already follows
    private var selection: Binding<Date?> {
        Binding(
            get: { highlighted },
            set: { value in
                guard let value, let bucket = buckets.last(where: { $0.start <= value }) else {
                    if scope == .day { selected = nil }
                    return
                }

                switch scope {
                case .week: anchor = bucket.start
                case .day: selected = bucket.start == selected ? nil : bucket.start
                }
            }
        )
    }

    private var periodAverage: Int? {
        let active = buckets.map { $0.value(metric) }.filter { $0 > 0 }.sorted()

        guard !active.isEmpty else { return buckets.isEmpty ? nil : 0 }

        let middle = active.count / 2
        return active.count.isMultiple(of: 2)
            ? (active[middle - 1] + active[middle]) / 2
            : active[middle]
    }

    private var lifetimeAverage: Int? {
        guard
            let average = ReadingBuckets.averageActive(
                sessions,
                of: scope == .day ? .hour : .day,
                metric: metric,
                calendar: calendar
            )
        else { return nil }

        return average
    }

    private var ceiling: Int {
        let peak = buckets.map { $0.value(metric) }.max() ?? 0
        let floor =
            metric == .pages
            ? (scope == .day ? Layout.dayFloor : Layout.weekFloor)
            : (scope == .day ? Layout.dayFloorChapters : Layout.weekFloorChapters)
        // reference lines must fit the axis too - an all-time average above a
        // quiet day's peak was drawn past the top of the plot previously
        let references = [periodAverage, lifetimeAverage].compactMap { $0 }.max() ?? 0
        let target = max(peak, floor, references)
        let step = target <= 100 ? 10 : (target <= 500 ? 50 : 100)
        return ((target + step - 1) / step) * step
    }

    // Charts' inferred date-scale domain extends to the start of the next unit,
    // which drew an eighth tick for the following Monday on a seven-day week
    private var domain: ClosedRange<Date> {
        guard let first = buckets.first?.start, let last = buckets.last?.start else {
            return anchor...anchor
        }
        return first...last
    }

    private var unit: Calendar.Component { scope == .day ? .hour : .day }

    private var barWidth: CGFloat { scope == .day ? Layout.dayBarWidth : Layout.weekBarWidth }

    private var axisValues: [Date] {
        switch scope {
        case .day: buckets.indices.filter { $0.isMultiple(of: 6) }.map { buckets[$0].start }
        case .week: buckets.map(\.start)
        }
    }

    private func axisLabel(_ date: Date) -> String {
        switch scope {
        case .day: date.formatted(.dateTime.hour())
        // narrow weekday symbols collide (Tue/Thu both T, Sat/Sun both S);
        // abbreviated is uneven width over seven bars, so this takes a fixed prefix
        case .week: String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(2))
        }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: asOf)
    }
}

// MARK: - Previews

#if DEBUG
    private enum Sample {
        static func sessions(days: Int, perDay: Int, pages: Int = 24) -> [ReadingSessionEntry] {
            var rows: [ReadingSessionEntry] = []
            let calendar = Calendar.current

            for day in 0..<days {
                for slot in 0..<perDay {
                    let hour = [8, 13, 19, 22, 23][slot % 5]
                    guard let base = calendar.date(byAdding: .day, value: -day, to: .now),
                        let start = calendar.date(
                            bySettingHour: hour, minute: 10, second: 0, of: base)
                    else { continue }

                    rows.append(
                        ReadingSessionEntry(
                            id: Int64(day * 10 + slot),
                            seriesId: 1,
                            seriesTitle: "Berserk",
                            pagesRead: pages + slot * 9 - day * 2,
                            chaptersRead: 1 + slot % 2,
                            startedDate: start,
                            endedDate: start.addingTimeInterval(TimeInterval(600 + slot * 900)),
                            localDayKey: start.localDayKey,
                            alive: true,
                            cover: nil,
                            path: nil
                        )
                    )
                }
            }
            return rows
        }
    }

    private struct ChartPreview: View {
        var sessions: [ReadingSessionEntry]
        var scope: ReadingChart.Scope = .week
        var metric: ReadingMetric = .pages

        @State private var liveScope: ReadingChart.Scope?
        @State private var liveMetric: ReadingMetric?
        @State private var anchor: Date = .now
        @State private var selected: Date?

        var body: some View {
            ReadingChart(
                sessions: sessions,
                scope: Binding(get: { liveScope ?? scope }, set: { liveScope = $0 }),
                metric: Binding(get: { liveMetric ?? metric }, set: { liveMetric = $0 }),
                anchor: $anchor,
                asOf: .now,
                earliest: Calendar.current.date(byAdding: .weekOfYear, value: -15, to: .now)
                    ?? .now,
                selected: $selected
            )
            .padding(16)
            .background(.canvas)
        }
    }

    #Preview("Week") {
        ChartPreview(sessions: Sample.sessions(days: 13, perDay: 3))
    }

    #Preview("Day") {
        ChartPreview(sessions: Sample.sessions(days: 13, perDay: 4), scope: .day)
    }

    #Preview("Chapters") {
        ChartPreview(sessions: Sample.sessions(days: 13, perDay: 3), metric: .chapters)
    }

    #Preview("Sparse") {
        ChartPreview(sessions: Sample.sessions(days: 1, perDay: 1))
    }

    #Preview("Empty") {
        ChartPreview(sessions: [])
    }
#endif

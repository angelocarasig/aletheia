//
//  ReadingChart.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Charts
import SwiftUI

// the Screen Time shape: a scope toggle over bars, scrub one to read it out.
//
// bars encode PAGES, in both scopes, and there is no metric switcher. minutes
// were the obvious analogue and are the worst datum we hold - comic reading is
// bursty, so a real day is a row of one-minute dust and the screen already had
// to stop rendering "0m" beside a full page count. chapters are 0/1/2 an hour,
// which has no shape at all. pages are exact, never zero for a real sitting, and
// carry variance at both grains. changing units on the toggle was rejected
// outright: a reader reads Day/Week as a zoom level, not a re-measurement.
struct ReadingChart: View {
    let sessions: [ReadingSessionEntry]
    @Binding var scope: Scope
    @Binding var metric: ReadingMetric
    // the period being viewed, which the stepper moves. today until it is moved
    @Binding var anchor: Date
    let asOf: Date
    // how far back the stepper may walk, which is the span the grid above draws.
    // bounding it by the earliest sitting instead let the chevron march into
    // months the screen never showed, every one of them empty
    let earliest: Date
    // owned by the screen: the session list below scopes to whatever is picked
    // here, so the selection is shared state rather than the chart's own
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
        // reserved whether or not a bar is selected, so scrubbing never reflows
        // the screen under the finger doing it
        static let readoutHeight: CGFloat = 44
        static let dayBarWidth: CGFloat = 8
        static let weekBarWidth: CGFloat = 34
        static let radius: CGFloat = 4
        // a peak-scaled axis makes a four-page day and a four-hundred-page day
        // look identical, which destroys the only comparison this chart exists
        // to support. a floor keeps a quiet day quiet
        static let dayFloor = 40
        static let weekFloor = 200
        // chapters are an order of magnitude smaller than pages, so they need
        // their own floors or every bar pins to the bottom of the axis
        static let dayFloorChapters = 4
        static let weekFloorChapters = 12
        static let unselectedOpacity: Double = 0.4
        // bare glyphs in a caption-height row are a ~16pt target sitting beside
        // a label they can be mistaken for, and a misfire moves a period with
        // no way back
        static let stepTarget: CGFloat = 44
        static let controlFill: Double = 0.06
        static let ruleGutter: CGFloat = 26
        static let stepDisabled: Double = 0.4
        static let keyWidth: CGFloat = 12
        static let keyHeight: CGFloat = 2
    }

    var body: some View {
        // the order iOS Screen Time uses, so nobody has to learn a new one:
        // scope segmented at the top, the period being viewed under it, then
        // the total for that period, then the bars
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
        // the unselected bars dim rather than snap, which is what ties the bar
        // being picked to the list changing under it
        .animation(.settle, value: selected)
        .onChange(of: scope) {
            selected = nil
            anchor = asOf
        }
        .onChange(of: metric) { selected = nil }
        .sensoryFeedback(.selection, trigger: selectedBucket?.start)
    }

    // MARK: Period

    // chevrons around the period label, forward disabled at the present - the
    // Health and Screen Time idiom for stepping a chart through time. without it
    // the chart could only ever answer for today, which is the one period the
    // reader already knows about
    private var Stepper: some View {
        // grouped so the two glass circles blend rather than reading as two
        // unrelated buttons either side of a label
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

    // a plain .disabled() barely moved: the glass kept its lensing and the glyph
    // its colour, so the edge of the record looked identical to the middle of
    // it. the surface goes flat and the glyph recedes, which is what says "this
    // is as far back as the screen goes" without a word
    @ViewBuilder
    private func Step(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let icon = Image(systemName: glyph)
            .foregroundStyle(enabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.muted))
            .frame(width: Layout.stepTarget, height: Layout.stepTarget)

        // the surface itself goes, rather than dimming by a fraction nobody can
        // measure against a neighbour. a glass circle beside a bare glyph is a
        // difference you cannot miss; two glass circles at slightly different
        // opacities is one nobody noticed
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

    // the previous period has to start no earlier than the window the grid
    // draws, and the next has to start no later than the one containing now
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

    // fixed height, always present. unselected it states the window; selected it
    // states the bucket. two lines either way, so nothing below it moves
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

            // a pop-up button showing its current value as text: a metric is
            // always set, so a permanent accent would say nothing
            Menu {
                Picker("Metric", selection: $metric) {
                    ForEach(ReadingMetric.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                // a capsule rather than bare text: as plain grey it was not
                // recognised as a control at all, and the one reader who
                // suspected it might be would not risk pressing it
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

    // branches rather than a String, and every branch owns its literal.
    // inflection markup only survives if it reaches Text unerased - a function
    // returning String, or a ternary with a String on either side, renders
    // "^[405 page](inflect: true)" on screen with no compiler warning. this
    // component shipped that bug; see design.md §13
    // always the period, never the selected bar. a headline that silently
    // switched meaning sat under a stepper reading "Today" and made readers do
    // arithmetic that could not work - 169 pages against 19 minutes - and
    // conclude the numbers were broken. the bar states its own value, in place
    private var Headline: some View {
        Amount(total)
    }

    // one place the unit is spoken, so a metric change cannot leave half the
    // copy behind. branches rather than a String - inflection dies the moment
    // the literal is assigned to one
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

    // the comparison is against the previous equivalent window, which is the
    // only one that means anything - the dashed average is a different question
    // and stays off the copy
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
            // no comparison rather than an apology for the absence of one:
            // "nothing to compare yet" read as something having failed
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

    // a line nobody can name is decoration. one row per rule, named in full on
    // the left and answered on the right, so the two numbers line up in a column
    // and can be read against each other rather than hunted for in a sentence
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

    // the number sits on the rule it belongs to rather than in the key below,
    // where it was a figure with no line beside it. the axis moved to the
    // leading edge to clear this space - two sets of numbers down one side is
    // where the old "Avg 57" ended up on top of a bar
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
                // a zero bucket draws nothing; the baseline rule below carries
                // the row, so a gap reads as empty rather than as missing chrome
                if bucket.value(metric) > 0 {
                    BarMark(
                        x: .value("When", bucket.start, unit: unit),
                        y: .value(metric.label, bucket.value(metric)),
                        width: .fixed(barWidth)
                    )
                    .clipShape(.rect(cornerRadius: Layout.radius))
                    .foregroundStyle(Palette.brand)
                    .opacity(
                        selected == nil || selectedBucket?.id == bucket.id
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

            // two references, both at the bar's own granularity so they can share
            // its axis: what a bar of yours usually looks like in THIS period,
            // and what one usually looks like across everything on record. the
            // pair is what turns a bar from a quantity into a comparison
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
            // drag alone loses to the parent scroll for anyone without a steady
            // hand, and there is no way back once it has. a tap is a single
            // committed act and it sticks
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
        // the rule values annotate outside the plot, so without a gutter they
        // render into the screen edge and clip
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

    private var selectedBucket: ReadingBuckets.Bucket? {
        guard let selected else { return nil }
        return buckets.last { $0.start <= selected }
    }

    // the chart's own selection writes wherever the finger landed; this snaps it
    // to the bucket that owns that instant and toggles, so tapping the same bar
    // twice puts the list below back to Recent Reading. writing through
    // selectXValue directly cannot do it - a second tap on one bar produces a
    // near-identical date, which is the same bucket and therefore no change
    private var selection: Binding<Date?> {
        Binding(
            get: { selected },
            set: { value in
                guard let value, let bucket = buckets.last(where: { $0.start <= value }) else {
                    selected = nil
                    return
                }
                selected = bucket.start == selected ? nil : bucket.start
            }
        )
    }

    // the median of the buckets that had reading in them, not a mean over the
    // empty ones - a mean across seven days with six zeroes describes nothing
    // that happened, and one enormous evening drags it somewhere no day ever
    // was. suppressed below two active buckets, where an average of one bar is
    // that bar
    private var periodAverage: Int? {
        let active = buckets.map { $0.value(metric) }.filter { $0 > 0 }.sorted()

        // a period with nothing in it still has an average, and it is zero.
        // dropping the line there left the all-time rule alone on the plot with
        // nothing to be compared against, which is the reading the pair exists
        // to give
        guard !active.isEmpty else { return buckets.isEmpty ? nil : 0 }

        let middle = active.count / 2
        return active.count.isMultiple(of: 2)
            ? (active[middle - 1] + active[middle]) / 2
            : active[middle]
    }

    // the same statistic over every sitting on record, at the same granularity,
    // so today can be read against your own habit rather than only against
    // itself. never suppressed for coinciding with the period line - two rules
    // sitting on each other still says something, and a reference that vanishes
    // when the numbers agree is missing at the one moment that is worth noticing
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

    // the peak rounded up to something readable, never below the floor
    private var ceiling: Int {
        let peak = buckets.map { $0.value(metric) }.max() ?? 0
        let floor =
            metric == .pages
            ? (scope == .day ? Layout.dayFloor : Layout.weekFloor)
            : (scope == .day ? Layout.dayFloorChapters : Layout.weekFloorChapters)
        // the reference lines are part of what the axis has to contain. left
        // out, an all-time average above a quiet day's peak was drawn past the
        // top of the plot and sat on the segmented control
        let references = [periodAverage, lifetimeAverage].compactMap { $0 }.max() ?? 0
        let target = max(peak, floor, references)
        let step = target <= 100 ? 10 : (target <= 500 ? 50 : 100)
        return ((target + step - 1) / step) * step
    }

    // bounded to the period's own buckets rather than left to the date scale,
    // which extends to the start of the next one - so a seven-day week drew an
    // eighth tick for the following Monday
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
        // every hour is an unreadable smear at this width, so four anchors
        case .day: buckets.indices.filter { $0.isMultiple(of: 6) }.map { buckets[$0].start }
        case .week: buckets.map(\.start)
        }
    }

    private func axisLabel(_ date: Date) -> String {
        switch scope {
        // "12" twice with nothing to separate midnight from midday. the locale's
        // own short hour carries the marker, or the 24-hour form where that is
        // what the reader uses
        case .day: date.formatted(.dateTime.hour())
        // two letters, uniform width, one per bar. the narrow form collides -
        // Tuesday and Thursday are both T, Saturday and Sunday both S - and the
        // abbreviated form is ragged, which is what produced six labels of
        // mixed width over seven bars
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

    // the same fortnight measured the other way - chapters are an order of magnitude
    // smaller, which is why the axis floor differs by metric
    #Preview("Chapters") {
        ChartPreview(sessions: Sample.sessions(days: 13, perDay: 3), metric: .chapters)
    }

    // one sitting in a fortnight - the chrome has to stay so the toggle does not
    // jump, and the overlay says which kind of empty this is
    #Preview("Sparse") {
        ChartPreview(sessions: Sample.sessions(days: 1, perDay: 1))
    }

    #Preview("Empty") {
        ChartPreview(sessions: [])
    }
#endif

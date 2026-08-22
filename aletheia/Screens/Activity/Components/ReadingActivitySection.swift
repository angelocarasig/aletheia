//
//  ReadingActivitySection.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

struct ReadingActivitySection: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: StatsViewModel?
    @AppStorage(Preferences.Key.statsScope) private var scope = Preferences.Default.statsScope
    @AppStorage(Preferences.Key.statsMetric) private var metric = Preferences.Default.statsMetric

    @State private var anchor: Date = .now
    @State private var selected: Date?
    // this screen is itself presented with navigationDestination(isPresented:), so a value push
    // declared anywhere else in it would land beneath the presenting screen instead of above it
    @State private var route: SeriesEntry?
    @State private var counted: Double = 0
    @State private var lifted = false
    @State private var rolled = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(vm: StatsViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private enum Layout {
        static let heatWeeks = 16
        static let fillOpacity = 0.05
        static let rollDuration: TimeInterval = 1.1
        static let rollLift: CGFloat = 1.05
        static let snapDuration: TimeInterval = 0.32

        static var heatStart: Date {
            Calendar.current.date(byAdding: .weekOfYear, value: -(heatWeeks - 1), to: .now) ?? .now
        }
    }

    private var highlight: DateInterval? {
        let calendar = Calendar.current
        return calendar.dateInterval(of: scope == .day ? .day : .weekOfYear, for: anchor)
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil {
                .failed
            } else if vm.snapshot == nil {
                .pending
            } else if vm.snapshot?.isEmpty == true {
                .empty
            } else {
                .content
            }
        } else {
            .pending
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .content:
                if let snapshot = vm?.snapshot {
                    Content(snapshot)
                        .transition(.opacity)
                }
            case .empty:
                ContentUnavailableView {
                    Label("No Reading Activity Yet", systemImage: "book.closed")
                } description: {
                    Text("Finish a chapter and it will be recorded here.")
                }
                .transition(.opacity)
            case .failed:
                if let vm, let failure = vm.failure {
                    ContentUnavailableView {
                        Label(failure.title, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure.message)
                    } actions: {
                        if failure.isRetryable {
                            Button("Try Again") { vm.retry() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .transition(.opacity)
                }
            default:
                ProgressView()
                    .transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationDestination(item: $route) { DetailsScreen(entry: $0) }
        .task {
            guard vm == nil else { return }
            let model = StatsViewModel(database: compositor.database)
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

extension ReadingActivitySection {
    fileprivate func Content(_ snapshot: StatsViewModel.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                SectionHeader("All Time")
                Totals(snapshot)
            }

            VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
                SectionHeader("Last 16 Weeks")

                ReadingHeatmap(
                    heat: snapshot.heat(for: metric),
                    weeks: Layout.heatWeeks,
                    asOf: .now,
                    highlight: highlight,
                    metric: metric,
                    onSelect: { anchor = $0 }
                )

                Runs(snapshot)

                ReadingChart(
                    sessions: snapshot.recent,
                    scope: $scope,
                    metric: $metric,
                    anchor: $anchor,
                    asOf: .now,
                    earliest: Layout.heatStart,
                    selected: $selected
                )
            }
            .onChange(of: anchor) { selected = nil }

            Group {
                if let bucket = activeBucket(snapshot) {
                    BucketSessions(bucket, sessions: snapshot.recent, granularity: activeGranularity)
                        .transition(.replace(reduceMotion: reduceMotion))
                }
            }
            .animation(.settle, value: selected)
            .animation(.settle, value: anchor)

        }
    }

    @ViewBuilder
    fileprivate func Totals(_ snapshot: StatsViewModel.Snapshot) -> some View {
        let tiles: [(target: Double, format: (Double) -> String, label: String)] = [
            (Double(snapshot.chaptersAllTime), { "\(Int($0))" }, "Chapters"),
            (Double(snapshot.secondsAllTime), { ReadingFormat.duration(Int($0)) }, "Time Read"),
            (Double(snapshot.pagesAllTime), { "\(Int($0))" }, "Pages"),
        ]

        Group {
            if dynamicTypeSize >= .accessibility1 {
                VStack(spacing: dimensions.spacing.space12) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                        Tile(label: tile.label) { Rolling(tile) }
                    }
                }
            } else {
                HStack(spacing: dimensions.spacing.space12) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                        Tile(label: tile.label) { Rolling(tile) }
                    }
                }
            }
        }
        // rolled has no persistence of its own - it lives as long as this view does, which the tab
        // keeps alive across visits, so relaunching the process is what actually resets it
        .task {
            guard !rolled else { return }
            rolled = true
            guard !reduceMotion else {
                counted = 1
                return
            }
            CountUpHaptic.play(duration: Layout.rollDuration)
            withAnimation(.easeOut(duration: Layout.rollDuration)) {
                counted = 1
                lifted = true
            } completion: {
                withAnimation(.snappy(duration: Layout.snapDuration, extraBounce: 0.3)) {
                    lifted = false
                }
            }
        }
    }

    fileprivate func Rolling(_ tile: (target: Double, format: (Double) -> String, label: String))
        -> some View
    {
        CountingText(value: counted * tile.target, format: tile.format)
    }

    @ViewBuilder
    fileprivate func Runs(_ snapshot: StatsViewModel.Snapshot) -> some View {
        if snapshot.currentRun > 1, snapshot.currentRun < snapshot.heat.count {
            HStack(spacing: dimensions.spacing.space4) {
                Text("^[\(snapshot.currentRun) day](inflect: true) running")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(verbatim: "·")
                    .foregroundStyle(.muted)

                Text("read on ^[\(snapshot.heat.count) day](inflect: true)")
                    .foregroundStyle(.muted)
            }
            .font(.caption)
        } else {
            Text("read on ^[\(snapshot.heat.count) day](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // ViewBuilder rather than a String, so a passed-in Text stays a literal at its own call site -
    // a String parameter here would render inflection markup verbatim with no warning
    fileprivate func Tile(label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: dimensions.spacing.space4) {
            value()
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12)
        )
        // scaleEffect per-tile, not on the row - scaling the group would slide the outer tiles sideways
        .scaleEffect(lifted ? Layout.rollLift : 1)
    }

    // the list's own granularity, independent of which day's bar got tapped -
    // day scope with an hour selected narrows to that hour, day scope with
    // nothing selected shows the whole day, week scope always shows the
    // whole week regardless of which day within it anchor points to
    fileprivate var activeGranularity: Calendar.Component {
        switch scope {
        case .day: selected != nil ? .hour : .day
        case .week: .weekOfYear
        }
    }

    fileprivate func activeBucket(_ snapshot: StatsViewModel.Snapshot) -> ReadingBuckets.Bucket? {
        switch scope {
        case .day:
            if let selected {
                return ReadingBuckets.hourly(snapshot.recent, on: anchor)
                    .first { $0.start == selected }
            }
            return ReadingBuckets.day(snapshot.recent, on: anchor)
        case .week:
            return ReadingBuckets.week(snapshot.recent, weekOf: anchor)
        }
    }

    fileprivate func BucketSessions(
        _ bucket: ReadingBuckets.Bucket, sessions: [ReadingSessionEntry],
        granularity: Calendar.Component
    ) -> some View {
        let rows = ReadingBuckets.sittings(sessions, in: bucket, of: granularity)

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                SectionHeader(bucketTitle(bucket, granularity: granularity))
                    .contentTransition(.opacity)

                Amount(bucket.value(metric))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if rows.isEmpty {
                Text(emptyMessage(for: granularity))
                    .font(.subheadline)
                    .foregroundStyle(.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, dimensions.spacing.space16)
            } else {
                ForEach(rows) { session in
                    SessionRow(session: session) { route = $0 }
                }
            }
        }
    }

    fileprivate func emptyMessage(for granularity: Calendar.Component) -> String {
        switch granularity {
        case .hour: "No reading in this hour"
        case .weekOfYear: "No reading this week"
        default: "No reading on this day"
        }
    }

    fileprivate func bucketTitle(_ bucket: ReadingBuckets.Bucket, granularity: Calendar.Component)
        -> String
    {
        let calendar = Calendar.current

        switch granularity {
        case .hour:
            return bucket.start.formatted(
                .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour())

        case .weekOfYear:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: bucket.start) else {
                return ""
            }
            if calendar.isDate(.now, equalTo: bucket.start, toGranularity: .weekOfYear) {
                return "This Week"
            }
            let end = interval.end.addingTimeInterval(-1)
            return
                "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) - \(end.formatted(.dateTime.day().month(.abbreviated)))"

        default:
            if calendar.isDateInToday(bucket.start) { return "Today" }
            if calendar.isDateInYesterday(bucket.start) { return "Yesterday" }
            return bucket.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }

    // each branch owns its literal - a String parameter here renders the inflection markup verbatim with no warning
    @ViewBuilder
    fileprivate func Amount(_ count: Int) -> some View {
        switch metric {
        case .pages: Text("^[\(count) page](inflect: true)")
        case .chapters: Text("^[\(count) chapter](inflect: true)")
        }
    }

}

// MARK: - Previews

#if DEBUG
    private enum Mock {
        static func heat(days: Int, over span: Int = 100) -> [Int: Int] {
            var heat: [Int: Int] = [:]
            let calendar = Calendar.current
            var placed = 0
            var offset = 0
            while placed < days, offset < span {
                if let date = calendar.date(byAdding: .day, value: -offset, to: .now) {
                    heat[date.localDayKey] = [1, 2, 3, 5, 9][placed % 5]
                    placed += 1
                }
                offset += offset.isMultiple(of: 3) ? 1 : 2
            }
            return heat
        }

        static func recent(days: Int) -> [ReadingSessionEntry] {
            var rows: [ReadingSessionEntry] = []
            let calendar = Calendar.current

            for day in 0..<max(days, 0) {
                for slot in 0..<3 {
                    let hour = [8, 13, 20][slot]
                    guard let base = calendar.date(byAdding: .day, value: -day, to: .now),
                        let start = calendar.date(
                            bySettingHour: hour, minute: 5, second: 0, of: base)
                    else { continue }

                    rows.append(
                        ReadingSessionEntry(
                            id: Int64(1_000 + day * 10 + slot),
                            seriesId: 1,
                            seriesTitle: "Berserk",
                            pagesRead: 22 + slot * 11 - day,
                            chaptersRead: 1 + slot % 2,
                            startedDate: start,
                            endedDate: start.addingTimeInterval(TimeInterval(700 + slot * 800)),
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

        static func snapshot(
            heatDays: Int = 34,
            chapters: Int = 412,
            seconds: Int = 187_000,
            pages: Int = 9_640,
            currentRun: Int = 6,
            longestRun: Int = 18
        ) -> StatsViewModel.Snapshot {
            .init(
                chaptersAllTime: chapters,
                secondsAllTime: seconds,
                pagesAllTime: pages,
                currentRun: currentRun,
                longestRun: longestRun,
                heat: heat(days: heatDays),
                heatChapters: heat(days: heatDays).mapValues { max(1, $0 / 18) },
                heatStartKey: 0,
                recent: recent(days: min(heatDays, 13))
            )
        }
    }

    #Preview("Populated") {
        NavigationStack {
            ScrollView {
                ReadingActivitySection(vm: .preview(snapshot: Mock.snapshot())).padding(16)
            }
        }
    }

    #Preview("Sparse") {
        NavigationStack {
            ScrollView {
                ReadingActivitySection(
                    vm: .preview(
                        snapshot: Mock.snapshot(
                            heatDays: 1,
                            chapters: 1,
                            seconds: 40,
                            pages: 49,
                            currentRun: 1,
                            longestRun: 1
                        )
                    )
                )
                .padding(16)
            }
        }
    }

    #Preview("Empty") {
        NavigationStack {
            ScrollView {
                ReadingActivitySection(
                    vm: .preview(
                        snapshot: Mock.snapshot(
                            heatDays: 0, chapters: 0, seconds: 0, pages: 0, currentRun: 0,
                            longestRun: 0))
                )
                .padding(16)
            }
        }
    }
#endif

// MARK: - Counting text

// Animatable interpolates animatableData and re-invokes body per frame, so the count
// animates through its own range without a timer
private struct CountingText: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

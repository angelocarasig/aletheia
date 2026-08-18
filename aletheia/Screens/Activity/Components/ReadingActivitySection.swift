//
//  ReadingActivitySection.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Kingfisher
import SwiftUI
import Tagged

// an aggregate with no drill-down turns every accuracy doubt into a dispute
// nothing can settle, so the numbers and the sessions that produced them ship as
// one surface.
//
// a section rather than a screen since 2026-08-11: it is the Activity tab's
// content, under the operational rows. it declares no ScrollView and no padding
// of its own - the tab owns one scroll for both halves, or the status rows would
// pin while the charts scrolled under them
struct ReadingActivitySection: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: StatsViewModel?
    // both remembered: a screen that resets how you were looking at it every
    // time you open it is one you have to re-aim on every visit
    @AppStorage(Preferences.Key.statsScope) private var scope = Preferences.Default.statsScope
    @AppStorage(Preferences.Key.statsMetric) private var metric = Preferences.Default.statsMetric

    // the period the chart is showing. the grid dims everything outside it, so
    // moving the stepper moves the emphasis - one selection, two resolutions
    @State private var anchor: Date = .now
    // the bar the chart has picked out, normalised to that bucket's start. owned
    // here rather than in the chart because the session list is what it scopes
    @State private var selected: Date?
    // the Details push has to be declared here: this screen is itself presented
    // with navigationDestination(isPresented:), so a value push from inside it
    // lands beneath it
    @State private var route: SeriesEntry?
    @State private var expanded = false
    // sessions or series: the same rows, folded or not. carried over when the
    // Activity tab stopped duplicating this data - grouping by series is the one
    // cut that feed had which nothing else did, and at a large library it is
    // triage ("what have I been ignoring") rather than a memory-lane view
    @State private var bySeries = false
    // 0 to 1, and every all-time tile multiplies its own total by it
    @State private var counted: Double = 0
    @State private var lifted = false
    @State private var rolled = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // built on appearance in the app; a preview hands one in already holding a
    // snapshot, which is what keeps the canvas off a database
    init(vm: StatsViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private enum Layout {
        static let heatWeeks = 16
        static let fillOpacity = 0.05
        static let groupingWidth: CGFloat = 140
        // SessionRow's own numbers: the two rows swap through one slot, so a
        // difference of a few points would read as the list jumping
        static let coverWidth: CGFloat = 58
        static let coverHeight: CGFloat = 70
        static let placeholderOpacity = 0.1
        static let collapsedSessions = 5
        // long enough for the deceleration to be legible, short enough that the
        // real numbers are not being withheld from someone who came to read them
        static let rollDuration: TimeInterval = 1.1
        // small: three cards swelling in unison reads as the section breathing,
        // and anything past a few percent reads as a layout bug instead
        static let rollLift: CGFloat = 1.05
        static let snapDuration: TimeInterval = 0.32

        static var heatStart: Date {
            Calendar.current.date(byAdding: .weekOfYear, value: -(heatWeeks - 1), to: .now) ?? .now
        }
    }

    // what the picker is currently showing, expressed as dates the grid can
    // outline. today, or the calendar week today falls in
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
        // declared here rather than by the tab: this is the only thing in the
        // stack that pushes a series, and the tab is presented with
        // navigationDestination(isPresented:) elsewhere, where a value push
        // would land beneath the screen doing the pushing
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
            // first now, not last. it was a footer because a fresh install
            // showed the same number under "All Time" and "This Week" and
            // everyone read that as a bug - but under the operational rows
            // the collision is gone, and these are the one part of this
            // section that does not grade you: the reader coming back after
            // a gap named them the only thing they were glad to see
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                SectionHeader("All Time")
                Totals(snapshot)
            }

            // ONE block, not two charts. the grid and the bars were the
            // same data at two spans, a screen apart, in the same blue -
            // which read as two libraries rather than one system. now the
            // picker drives both: the bars show the span, and the grid
            // outlines the days those bars are made of, so a reader can see
            // where this week sits inside four months without being told.
            //
            // no section header either: the readout inside the chart is the
            // title, and a header above it was the second one for one thing
            VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
                // the block opens on a caption and a grid, so the readout
                // inside the chart arrives too late to title anything. a
                // header rather than moving the number above the map
                SectionHeader("Last 16 Weeks")

                // grid first: it is the map, and the bars below are the
                // detail of whichever part of it the stepper has picked out
                ReadingHeatmap(
                    heat: snapshot.heat(for: metric),
                    weeks: Layout.heatWeeks,
                    asOf: .now,
                    highlight: highlight,
                    metric: metric,
                    // tapping a day moves the chart to the period that day
                    // falls in, at whatever granularity is currently
                    // selected - the picker says what a tap means, so a tap
                    // must not silently change the picker
                    onSelect: { anchor = $0 }
                )

                Runs(snapshot)

                ReadingChart(
                    sessions: snapshot.recent,
                    scope: $scope,
                    metric: $metric,
                    anchor: $anchor,
                    asOf: .now,
                    // the same span the grid draws, so the stepper can reach
                    // every cell above it and nothing beyond
                    earliest: Layout.heatStart,
                    selected: $selected
                )
            }

            // a grid tap moves the period, which makes any bar selection
            // stale - and it writes anchor directly rather than through the
            // chart's stepper, so the chart never sees it
            .onChange(of: anchor) { selected = nil }

            // the two lists occupy one slot and swap through each other, so
            // picking a bar reads as the list changing what it is about
            // rather than as the screen reflowing under the finger
            Group {
                if let bucket = selectedBucket(snapshot) {
                    BucketSessions(bucket, sessions: snapshot.recent)
                        .transition(.replace(reduceMotion: reduceMotion))
                } else if !snapshot.sessions.isEmpty {
                    Sessions(snapshot.sessions)
                        .transition(.replace(reduceMotion: reduceMotion))
                }
            }
            .animation(.settle, value: selected)

        }
    }

    // three across is the first thing on this screen to break as text grows -
    // "Time Read" alone overflows a third of the width well before the largest
    // settings - so past the accessibility sizes the row becomes a column and
    // each tile takes the full width
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
        // once per launch, and the flag lives on the screen because that is
        // exactly the lifetime asked for: the tab keeps this alive across visits
        // and the process is what ends it. no preference, nothing persisted -
        // reopening the app is the whole trigger
        .task {
            guard !rolled else { return }
            rolled = true
            guard !reduceMotion else {
                counted = 1
                return
            }
            CountUpHaptic.play(duration: Layout.rollDuration)
            // the cards swell while the numbers climb and snap back when they
            // land, so the ramp's last tap is the release of something the eye
            // watched build rather than a beep at the end of a counter.
            //
            // the snap rides withAnimation's completion rather than a sleep -
            // it fires when the roll genuinely finishes, which is also the beat
            // the haptic pattern already scheduled its pop on. two clocks, one
            // instant, and neither is waiting on the other
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

    // the digits and the ramp read the same fraction, so they decelerate
    // together - one number animated once, rather than three counters and a
    // schedule that could drift apart
    fileprivate func Rolling(_ tile: (target: Double, format: (Double) -> String, label: String))
        -> some View
    {
        CountingText(value: counted * tile.target, format: tile.format)
    }

    // a caption on the grid rather than two tiles under it: a run is the grid's
    // own summary, not a third statistic, and as boxed tiles it read as a
    // stranded second group with the legend wedged between.
    //
    // the second number is a TOTAL, not a personal best. "best 18 days" beside a
    // current run of 1 is a scoreboard - it hands a returning reader a figure
    // they have already fallen short of, which is the loss mechanic
    // home-screen.md rules out and the one thing a reader coming back after a
    // gap said would stop them opening the app. a total only ever goes up, so
    // there is nothing to fail at, and it summarises the same grid the run does
    // on day one both halves said "1 day" and the caption read as one fact
    // stammered twice. the total is the honest half - it only ever goes up - so
    // the run joins it only once the two can differ. scoped to the grid above
    // rather than to all time, so it states what the reader can actually count
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

    // a builder rather than a Text, so the value can be a view that animates
    // itself. it took Text because a String parameter is one of the four silent
    // inflection killers - a builder keeps that safe, since a Text passed in is
    // still a literal at its own call site
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
        // each card about its own centre rather than the row about the row's:
        // scaling the group would slide the outer two sideways, which reads as
        // the layout shifting instead of the cards swelling
        .scaleEffect(lifted ? Layout.rollLift : 1)
    }

    fileprivate var granularity: Calendar.Component { scope == .day ? .hour : .day }

    // the bar the chart has picked, resolved against the same sittings the bars
    // were built from. recomputing the spine here rather than passing the bucket
    // up keeps the chart's selection a plain date
    fileprivate func selectedBucket(_ snapshot: StatsViewModel.Snapshot) -> ReadingBuckets.Bucket? {
        guard let selected else { return nil }

        let buckets =
            scope == .day
            ? ReadingBuckets.hourly(snapshot.recent, on: anchor)
            : ReadingBuckets.daily(snapshot.recent, weekOf: anchor)

        return buckets.first { $0.start == selected }
    }

    // Recent Reading, re-scoped to one bar. the rows are whole sittings with
    // their own values, so a sitting that straddled the bucket reads larger than
    // the caption above it - the caption answers what the bar said, the rows
    // answer what happened, and the clock time on the row is the difference
    fileprivate func BucketSessions(
        _ bucket: ReadingBuckets.Bucket, sessions: [ReadingSessionEntry]
    ) -> some View {
        let rows = ReadingBuckets.sittings(sessions, in: bucket, of: granularity)

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            // moving from one bar to the next keeps this block on screen, so the
            // words have to carry the change themselves - without it the header
            // is the one part of the swap that jumps
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                SectionHeader(bucketTitle(bucket))
                    .contentTransition(.opacity)

                Amount(bucket.value(metric))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if rows.isEmpty {
                Text(scope == .day ? "No reading in this hour" : "No reading on this day")
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

    // the date is carried, not just the hour: the bar's own annotation says only
    // "13:00" and the stepper naming the day has scrolled off by the time this
    // list is being read
    fileprivate func bucketTitle(_ bucket: ReadingBuckets.Bucket) -> String {
        switch scope {
        case .day:
            bucket.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour())
        case .week: bucket.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }

    // branches, each owning its literal - a String here renders the inflection
    // markup verbatim with no warning
    @ViewBuilder
    fileprivate func Amount(_ count: Int) -> some View {
        switch metric {
        case .pages: Text("^[\(count) page](inflect: true)")
        case .chapters: Text("^[\(count) chapter](inflect: true)")
        }
    }

    // the cap counts rows, not days: five sittings deep is the same amount of
    // screen whether they happened across one evening or five
    fileprivate func Sessions(_ sessions: [ReadingSessionEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader(title: "Recent Reading") {
                Grouping
            }

            if bySeries {
                SeriesList(sessions)
            } else {
                DayList(sessions)
            }
        }
        .animation(.settle, value: bySeries)
    }

    // in the header rather than the toolbar: it scopes this section and nothing
    // else on the screen, and the toolbar is two scroll-lengths away from what
    // it would be changing
    fileprivate var Grouping: some View {
        Picker("Grouping", selection: $bySeries) {
            Text("Days").tag(false)
            Text("Series").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: Layout.groupingWidth)
    }

    fileprivate func DayList(_ sessions: [ReadingSessionEntry]) -> some View {
        let visible = expanded ? sessions : Array(sessions.prefix(Layout.collapsedSessions))
        let byDay = Dictionary(grouping: visible, by: \.localDayKey)

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                    Text(ReadingFormat.dayLabel(for: day))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(byDay[day] ?? []) { session in
                        SessionRow(session: session) { route = $0 }
                    }
                }
            }

            if sessions.count > Layout.collapsedSessions {
                ExpandToggle(sessions.count)
            }
        }
    }

    // folded from the same rows rather than queried again: a session already
    // carries its series, so the grouping is a view of what is loaded and not a
    // second trip. ordered by how recently each series was read, which is what
    // makes the top of the list the thing you are actually in the middle of
    fileprivate func SeriesList(_ sessions: [ReadingSessionEntry]) -> some View {
        let groups = Self.series(from: sessions)
        let visible = expanded ? groups : Array(groups.prefix(Layout.collapsedSessions))

        return VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            ForEach(visible) { group in
                SeriesRow(group)
            }

            if groups.count > Layout.collapsedSessions {
                ExpandToggle(groups.count, noun: "Series")
            }
        }
    }

    // the same anatomy as SessionRow, because it is the same row folded: artwork,
    // then what and when, then how much. a grouping toggle that also changed the
    // shape of every row would read as two screens rather than two views
    fileprivate func SeriesRow(_ group: SeriesTotal) -> some View {
        let row = HStack(spacing: dimensions.spacing.space12) {
            Cover(group)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
                    Text(group.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .foregroundStyle(group.alive ? .primary : .secondary)

                    Spacer(minLength: 0)

                    // sittings, not days: the row is folded from sessions, and
                    // two in one evening is two sittings however the calendar
                    // counts them. it takes the slot the clock holds on a
                    // session row - both answer "how often", at two grains
                    Text("^[\(group.sittings) sitting](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                }

                Text(summary(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))

        return Group {
            if group.alive {
                row
                    .contentShape(.rect)
                    .tappable { route = .library(SeriesRecord.ID(rawValue: group.seriesId)) }
            } else {
                row
            }
        }
    }

    fileprivate func Cover(_ group: SeriesTotal) -> some View {
        let local = compositor.assets.local(for: group.path)

        return Color.clear
            .frame(width: Layout.coverWidth, height: Layout.coverHeight)
            .overlay {
                if let cover = local ?? group.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer()
                        }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.primary.opacity(Layout.placeholderOpacity))
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }

    fileprivate func summary(_ group: SeriesTotal) -> String {
        var parts: [String] = []
        if group.chapters > 0 { parts.append("\(group.chapters) finished") }
        if group.pages > 0 { parts.append("\(group.pages) pages") }
        if group.seconds > 0 { parts.append(ReadingFormat.duration(group.seconds)) }
        return parts.isEmpty ? "Read" : parts.joined(separator: " · ")
    }

    fileprivate static func series(from sessions: [ReadingSessionEntry]) -> [SeriesTotal] {
        Dictionary(grouping: sessions, by: \.seriesId)
            .compactMap { id, rows -> SeriesTotal? in
                guard let newest = rows.max(by: { $0.endedDate < $1.endedDate }) else { return nil }
                return SeriesTotal(
                    seriesId: id,
                    title: newest.seriesTitle,
                    alive: newest.alive,
                    cover: newest.cover,
                    path: newest.path,
                    chapters: rows.reduce(0) { $0 + $1.chaptersRead },
                    pages: rows.reduce(0) { $0 + $1.pagesRead },
                    seconds: rows.reduce(0) { $0 + $1.seconds },
                    latest: newest.endedDate,
                    sittings: rows.count
                )
            }
            .sorted { $0.latest > $1.latest }
    }

    // the chapter list's control, same shape and same words - two lists on two
    // screens that both open short should not expand differently
    fileprivate func ExpandToggle(_ count: Int, noun: String = "Sessions") -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .contentTransition(.symbolEffect(.replace))

            Text(expanded ? "Show Less" : "Show All \(count) \(noun)")
        }
        .font(.subheadline)
        .foregroundStyle(.brand)
        .frame(maxWidth: .infinity)
        .padding(dimensions.spacing.space16)
        .background(
            Palette.brand.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius8)
        )
        .tappable {
            withAnimation { expanded.toggle() }
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

        static func sessions(_ count: Int) -> [ReadingSessionEntry] {
            (0..<count).map { index in
                let started: Date = .now.addingTimeInterval(TimeInterval(-index * 7_200))
                // the first one is deliberately seconds long - the case that used
                // to render "0m" beside a full page count
                let length = index == 0 ? 40 : 900 + index * 300
                return ReadingSessionEntry(
                    id: Int64(index + 1),
                    seriesId: Int64(index + 1),
                    seriesTitle: ["Berserk", "Vagabond", "Blade of the Waning Moon"][index % 3],
                    pagesRead: 49 - index * 6,
                    chaptersRead: index.isMultiple(of: 2) ? 1 : 0,
                    startedDate: started,
                    endedDate: started.addingTimeInterval(TimeInterval(length)),
                    localDayKey: started.localDayKey,
                    alive: true,
                    cover: nil,
                    path: nil
                )
            }
        }

        // the fortnight the chart buckets - separate from the Sessions fixture,
        // which is a shorter list meant to be read rather than aggregated
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
            longestRun: Int = 18,
            sessions sessionCount: Int = 4
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
                sessions: sessions(sessionCount),
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

    // the sparse end: one reading day against a full grid of empties, which is what
    // a first-day install actually looks like
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
                            longestRun: 1,
                            sessions: 1
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
                            longestRun: 0, sessions: 0))
                )
                .padding(16)
            }
        }
    }
#endif

// one series' share of a window, folded from its sittings. not a database shape:
// the sessions are already loaded, so this exists only to say what they add up to
struct SeriesTotal: Identifiable {
    let seriesId: Int64
    let title: String
    let alive: Bool
    // taken from the newest sitting rather than fetched: every session already
    // carries its series' artwork, and the newest one holds the freshest cover
    let cover: URL?
    let path: String?
    let chapters: Int
    let pages: Int
    let seconds: Int
    let latest: Date
    let sittings: Int

    var id: Int64 { seriesId }
}

// MARK: - Counting text

// a number that animates through its own range rather than cutting to it.
// Animatable is what makes that possible without a timer: SwiftUI interpolates
// `animatableData` and re-invokes `body` per frame, so the curve, the duration
// and the cancellation all belong to the animation that set the value.
//
// monospaced, or the digits change width as they roll and the tile jitters
// under its own label
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

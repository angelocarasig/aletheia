//
//  UpdatesScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Charts
import SwiftUI
import Tagged

struct UpdatesScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: UpdatesViewModel?
    // declared here, not inherited from the parent: a value push from inside a
    // navigationDestination(isPresented:) screen lands beneath it if declared above
    @State private var reading: ReadingTarget?
    @State private var route: SeriesEntry?
    @State private var selectedDay: Date?

    @AppStorage(Preferences.Key.blurAdultHome) private var blurAdult = Preferences.Default
        .blurAdultHome

    init(vm: UpdatesViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private struct ReadingTarget: Identifiable, Hashable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID
        var id: ChapterRecord.ID { chapterId }
    }

    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil {
                .failed
            } else if vm.entries == nil {
                .pending
            } else if vm.isEmpty {
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
                if let entries = vm?.entries {
                    Content(entries, activity: vm?.activity ?? [])
                        .transition(.opacity)
                }
            case .empty:
                ContentUnavailableView {
                    Label("No New Chapters", systemImage: "bell.slash")
                } description: {
                    Text("Series you follow will appear here when they update.")
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
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { DetailsScreen(entry: $0) }
        .navigationDestination(item: $reading) { target in
            ReaderScreen(seriesId: target.seriesId, chapterId: target.chapterId)
        }
        .task {
            guard vm == nil else { return }
            let model = UpdatesViewModel(
                database: compositor.database,
                assets: compositor.assets,
                registry: compositor.registry
            )
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

extension UpdatesScreen {
    fileprivate func Content(_ entries: [HomeViewModel.UpdateEntry], activity: [Date]) -> some View {
        let buckets = UpdateBuckets.week(activity)
        // series-level, not chapter-level: entries only carry each series'
        // single latest new-chapter date, so a tapped day can only match
        // series whose latest happens to land there
        let filtered =
            selectedDay.map { day in
                entries.filter { Calendar.current.isDate($0.latest, inSameDayAs: day) }
            } ?? entries

        return ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                StatsSection(entries, buckets: buckets)

                SectionHeader(selectedDay.map(dayLabel) ?? "All Updates")

                if selectedDay != nil, filtered.isEmpty {
                    Text("No series updated on this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, dimensions.spacing.space24)
                } else {
                    GlassEffectContainer(spacing: dimensions.spacing.space12) {
                        VStack(spacing: dimensions.spacing.space12) {
                            ForEach(filtered) { entry in
                                UpdateCard(
                                    title: entry.title,
                                    cover: entry.cover,
                                    count: entry.count,
                                    latest: entry.latest,
                                    obscured: obscured && entry.adult
                                )
                                .contentShape(.rect)
                                .tappable {
                                    route = .library(entry.id)
                                }
                                .contextMenu {
                                    Button {
                                        reading = ReadingTarget(
                                            seriesId: entry.id, chapterId: entry.target.chapterId)
                                    } label: {
                                        Label(
                                            "Read \(ReadingFormat.chapter(entry.target.number))",
                                            systemImage: "book.pages")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .animation(.settle, value: selectedDay)
    }

    // all three tiles scoped to today, unlike the list below (unwindowed
    // backlog) and the chart (last 7 days) - three different questions, kept
    // visually distinct so none of them silently borrow another's scope
    fileprivate func StatsSection(_ entries: [HomeViewModel.UpdateEntry], buckets: [UpdateBuckets.Bucket])
        -> some View
    {
        let todaySeries = entries.filter { Calendar.current.isDateInToday($0.latest) }
        let yesterdaySeries = entries.filter { Calendar.current.isDateInYesterday($0.latest) }
        // buckets end on today (UpdateBuckets.week's default `ending day`),
        // so the last two entries are today and yesterday's chapter-level
        // publish counts - the same numbers the chart's own bars show
        let todayChapters = buckets.last?.count ?? 0
        let yesterdayChapters = buckets.count >= 2 ? buckets[buckets.count - 2].count : 0
        let unreadToday = todaySeries.reduce(0) { $0 + $1.count }
        let unreadYesterday = yesterdaySeries.reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: dimensions.spacing.space12) {
                    StatTile(
                        label: "Series Updated", value: "\(todaySeries.count)",
                        trend: (current: todaySeries.count, previous: yesterdaySeries.count))
                    StatTile(
                        label: "New Chapters", value: "\(todayChapters)",
                        trend: (current: todayChapters, previous: yesterdayChapters))
                    StatTile(
                        label: "Unread", value: "\(unreadToday)",
                        trend: (current: unreadToday, previous: unreadYesterday))
                }
            }

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("Update Activity")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("New chapters by publish date, last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActivityChart(buckets)
        }
    }

    fileprivate func StatTile(
        label: String, value: String, trend: (current: Int, previous: Int)? = nil
    ) -> some View {
        VStack(spacing: dimensions.spacing.space4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            // reserved on every tile, trend or not - a row only the trended
            // tile has would leave the other two shorter, misaligning all
            // three card heights in the HStack
            Group {
                if let trend {
                    TrendBadge(trend)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: Layout.trendRowHeight)
            .padding(.top, dimensions.spacing.space8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dimensions.spacing.space12)
        .padding(.horizontal, dimensions.spacing.space8)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    fileprivate func TrendBadge(_ trend: (current: Int, previous: Int)) -> some View {
        let delta = trend.current - trend.previous
        let icon = delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "arrow.right"
        let tint: Color = delta > 0 ? Palette.successText : .secondary

        // the icon already carries the direction, and the tile's own big
        // number already shows "today" - only yesterday's raw count adds
        // anything new here
        return HStack(spacing: dimensions.spacing.space2) {
            Image(systemName: icon)
            Text("\(trend.previous) yesterday")
        }
        // fixed, not .caption2 - a semantic style here scales with Dynamic
        // Type and reads too large for a corner annotation
        .font(.system(size: Layout.trendFontSize))
        .fontDesign(.monospaced)
        .foregroundStyle(tint)
    }

    // tap wiring matches ReadingChart's exact pattern: chartXSelection alone
    // doesn't respond to a plain tap, chartGesture's SpatialTapGesture does
    fileprivate func ActivityChart(_ buckets: [UpdateBuckets.Bucket]) -> some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Day", bucket.start, unit: .day),
                y: .value("Chapters", bucket.count),
                width: .fixed(Layout.barWidth)
            )
            .clipShape(.rect(cornerRadius: Layout.barRadius))
            .foregroundStyle(Palette.brand)
            .opacity(
                selectedDay == nil || selectedDay == bucket.start ? 1 : Layout.unselectedOpacity)
        }
        .chartXSelection(value: selection(over: buckets))
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: buckets.map(\.start)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(2)))
                            .font(.caption2)
                            .foregroundStyle(.muted)
                    }
                }
            }
        }
        .frame(height: Layout.chartHeight)
        .animation(.snappy, value: selectedDay)
    }

    private func selection(over buckets: [UpdateBuckets.Bucket]) -> Binding<Date?> {
        Binding(
            get: { nil },
            set: { value in
                guard let value,
                    let match = buckets.first(where: {
                        Calendar.current.isDate($0.start, inSameDayAs: value)
                    })
                else { return }
                selectedDay = selectedDay == match.start ? nil : match.start
            }
        )
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private enum Layout {
        static let fillOpacity = 0.05
        static let chartHeight: CGFloat = 168
        static let barWidth: CGFloat = 34
        static let barRadius: CGFloat = 4
        static let unselectedOpacity = 0.35
        static let trendFontSize: CGFloat = 9
        static let trendRowHeight: CGFloat = 14
    }
}

// MARK: - Previews

#if DEBUG
    private enum Mock {
        static let titles = [
            "Blue Lock", "The Exiled Heavy Knight Knows How to Game the System", "Mia is back",
        ]
        static let counts = [213, 163, 44]

        static func entry(_ index: Int) -> HomeViewModel.UpdateEntry {
            let id = SeriesRecord.ID(rawValue: Int64(index + 1))
            let latest: Date = .now.addingTimeInterval(TimeInterval(-3_600 * (index + 1)))

            return HomeViewModel.UpdateEntry(
                id: id,
                title: titles[index % titles.count],
                cover: nil,
                count: counts[index % counts.count],
                latest: latest,
                target: .start(chapterId: ChapterRecord.ID(rawValue: Int64(index + 1)), number: 1),
                adult: false
            )
        }

        static func entries(_ count: Int) -> [HomeViewModel.UpdateEntry] {
            (0..<count).map(entry)
        }

        static let activity: [Date] = {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let perDay = [0: 4, 1: 1, 2: 0, 3: 6, 4: 2, 5: 3, 6: 1]

            return perDay.flatMap { offset, count -> [Date] in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                    return []
                }
                return (0..<count).map { day.addingTimeInterval(TimeInterval($0 * 3_600)) }
            }
        }()
    }

    #Preview("Populated") {
        NavigationStack {
            UpdatesScreen(vm: .preview(entries: Mock.entries(9), activity: Mock.activity))
        }
    }

    #Preview("Empty") {
        NavigationStack {
            UpdatesScreen(vm: .preview(entries: [], activity: []))
        }
    }
#endif

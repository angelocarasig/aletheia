//
//  HomeScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import Tagged

struct HomeScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: HomeViewModel?
    @State private var path = NavigationPath()
    @State private var reading: ReadingTarget?
    @State private var browsing = false
    @State private var showingStats = false

    // the model is built on appearance in the app; a preview hands one in
    // already holding its snapshot, which is what keeps previews off a database
    init(vm: HomeViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private struct ReadingTarget: Identifiable, Hashable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID
        var id: ChapterRecord.ID { chapterId }
    }

    private enum Layout {
        static let addedColumns = 2
        static let addedRows = 2
        static let heroSpan = 8
    }

    // the range reads under the title, so the numbers below never have to carry
    // the question of what they are counting
    private var subtitle: Text {
        guard phase == .content, let vm else { return Text(verbatim: "") }
        return Text(vm.range.label)
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil { .failed }
            else if vm.snapshot == nil { .pending }
            else if vm.isEmpty { .empty }
            else { .content }
        } else {
            .pending
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                switch phase {
                case .content:
                    if let vm {
                        Content(vm)
                            .transition(.opacity)
                    }
                case .empty:
                    Empty
                        .transition(.opacity)
                case .failed:
                    if let vm, let failure = vm.failure {
                        Unavailable(failure)
                            .transition(.opacity)
                    }
                default:
                    Skeleton
                        .transition(.opacity)
                }
            }
            .animation(.settle, value: phase)
            .navigationTitle("Home")
            .navigationSubtitle(subtitle)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbarTitleMenu {
                // the window is what the title is scoped by, so it belongs to the
                // title rather than a trailing button. the control exists only
                // where there are numbers to rescope - an empty or failed Home
                // has nothing for a window to change
                if phase == .content, let vm {
                    RangePicker(vm)
                }
            }
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
            .navigationDestination(item: $reading) { target in
                ReaderScreen(seriesId: target.seriesId, chapterId: target.chapterId)
            }
            .navigationDestination(isPresented: $browsing) {
                SearchScreen(query: "", embedded: true)
            }
            .navigationDestination(isPresented: $showingStats) {
                StatsScreen()
            }
            .task {
                guard vm == nil else { return }
                let model = HomeViewModel(
                    database: compositor.database,
                    assets: compositor.assets,
                    registry: compositor.registry
                )
                vm = model
                model.observe()
            }
        }
    }
}

// MARK: - Content

private extension HomeScreen {
    func Content(_ vm: HomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                let continueReading = vm.continueReading
                if !continueReading.isEmpty {
                    ContinueSection(vm, entries: continueReading)
                }

                if let stats = vm.stats, !stats.isEmpty {
                    StatStrip(stats)
                        .padding(.horizontal, dimensions.screenMargin)
                }

                let added = vm.recentlyAdded
                if !added.isEmpty {
                    AddedSection(entries: added)
                }

                let sessions = vm.sessions
                if !sessions.isEmpty {
                    SessionsSection(sessions)
                        .padding(.horizontal, dimensions.screenMargin)
                }
            }
            .padding(.vertical, dimensions.spacing.space16)
        }
    }

    func ContinueSection(_ vm: HomeViewModel, entries: [HomeViewModel.ContinueEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Continue Reading")
                .padding(.horizontal, dimensions.screenMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: dimensions.spacing.space12) {
                    ForEach(entries) { entry in
                        ContinueCard(
                            title: entry.title,
                            cover: entry.cover,
                            unreadCount: entry.unreadCount,
                            target: entry.target
                        )
                        // the card is the hero of the screen, so it takes the
                        // width of the screen less the peek that says there is
                        // another one behind it
                        .containerRelativeFrame(
                            .horizontal,
                            count: Layout.heroSpan,
                            span: Layout.heroSpan - 1,
                            spacing: dimensions.spacing.space12
                        )
                        .contentShape(.rect)
                        .tappable {
                            reading = ReadingTarget(seriesId: entry.id, chapterId: entry.target.chapterId)
                        }
                        .contextMenu {
                            Button {
                                path.append(SeriesEntry.library(entry.id))
                            } label: {
                                Label("View Series", systemImage: "book")
                            }

                            Button {
                                vm.dismiss(entry.id)
                            } label: {
                                Label("Hide from Continue Reading", systemImage: "eye.slash")
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, dimensions.screenMargin)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    func RangePicker(_ vm: HomeViewModel) -> some View {
        // read here, not inside the binding's getter: a getter runs when the
        // value is asked for rather than during body evaluation, so the read
        // never registers as a dependency and the tick would stop moving
        let range = vm.range

        return Picker("Range", selection: Binding(get: { range }, set: { vm.select($0) })) {
            ForEach(StatRange.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.inline)
    }

    // tiles only - the numbers' rows live one tap deeper, and the whole strip
    // is that tap. record-framed: a run is a fact, never a countdown. the window
    // is named once, in the subtitle, rather than on every label
    func StatStrip(_ stats: HomeViewModel.StatTiles) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            StatTile(value: Text("\(stats.chaptersInRange)"), label: "Chapters")
            StatTile(value: Text(ReadingFormat.duration(stats.secondsInRange)), label: "Time Read")
            StatTile(value: Text("^[\(stats.currentRun) day](inflect: true)"), label: "Current Run")
        }
        .contentShape(.rect)
        .tappable { showingStats = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading activity. Opens details.")
    }

    func StatTile(value: Text, label: String) -> some View {
        VStack(spacing: dimensions.spacing.space4) {
            value
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dimensions.spacing.space12)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    // four covers, large: Library shows many small, so scale is what tells the
    // two apart - and the date under each is what Home adds that Library cannot
    func AddedSection(entries: [HomeViewModel.AddedEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Recently Added")

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: dimensions.screenMargin),
                    count: Layout.addedColumns
                ),
                alignment: .leading,
                spacing: dimensions.spacing.space24
            ) {
                ForEach(entries.prefix(Layout.addedColumns * Layout.addedRows)) { entry in
                    NavigationLink(value: SeriesEntry.library(entry.id)) {
                        AddedCard(
                            title: entry.title,
                            cover: entry.cover,
                            unreadCount: entry.unreadCount,
                            addedDate: entry.addedDate
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, dimensions.screenMargin)
    }

    // the sittings behind the tiles, over the same window. five of them, with
    // the rest of the record one tap deeper
    func SessionsSection(_ sessions: [ReadingSessionEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader(title: "Recent Sessions") {
                Text("All")
                    .font(.subheadline)
                    .foregroundStyle(.brand)
                    .contentShape(.rect)
                    .tappable { showingStats = true }
            }

            ForEach(sessions) { session in
                SessionRow(session: session)
            }
        }
    }
}

// MARK: - States

private extension HomeScreen {
    var Empty: some View {
        ContentUnavailableView {
            Label("Nothing to Read Yet", systemImage: "book.closed")
        } description: {
            Text("Series you read and add to your library will appear here.")
        } actions: {
            Button("Find Series") { browsing = true }
                .buttonStyle(.borderedProminent)
        }
    }

    func Unavailable(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        } actions: {
            if failure.isRetryable {
                Button("Try Again") { vm?.retry() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    var Skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Continue Reading")

                    // the same horizontal scroll container the content path uses:
                    // containerRelativeFrame has nothing to measure against
                    // without one, and resolves to an infinite width
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: dimensions.spacing.space12) {
                            ForEach(0..<2, id: \.self) { _ in
                                ContinueCard(
                                    title: "",
                                    cover: nil,
                                    unreadCount: 0,
                                    target: .start(chapterId: .init(rawValue: 0), number: 0)
                                )
                                .containerRelativeFrame(
                                    .horizontal,
                                    count: Layout.heroSpan,
                                    span: Layout.heroSpan - 1,
                                    spacing: dimensions.spacing.space12
                                )
                            }
                        }
                    }
                    .scrollDisabled(true)
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Recently Added")

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: dimensions.screenMargin),
                            count: Layout.addedColumns
                        ),
                        alignment: .leading,
                        spacing: dimensions.spacing.space24
                    ) {
                        ForEach(0..<(Layout.addedColumns * Layout.addedRows), id: \.self) { _ in
                            AddedCard(title: nil, cover: nil, unreadCount: 0, addedDate: nil)
                        }
                    }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollDisabled(true)
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#if DEBUG
private enum Mock {
    static let titles: [String] = [
        "A Former Hero Returned From Another World",
        "Heavenly Solo Defender",
        "The Villainess Wants a Quiet Life",
        "Blade of the Waning Moon",
        "Nine Lives of the Sword Saint",
        "Café at the End of the Line",
        "Regressor's Instruction Manual",
        "Tower of Ash"
    ]

    static let stats = HomeViewModel.StatTiles(chaptersInRange: 23, secondsInRange: 9_240, currentRun: 12)

    static func title(_ index: Int) -> String {
        titles[index % titles.count]
    }

    // even entries are partway through a chapter, odd ones are waiting on the
    // next - both subtitles want to be visible in one preview
    static func target(_ index: Int) -> ContinueTarget {
        let id = ChapterRecord.ID(rawValue: Int64(index + 1))
        if index.isMultiple(of: 2) {
            return .resume(chapterId: id, number: Double(40 + index), progress: 0.45)
        } else {
            return .start(chapterId: id, number: Double(12 + index))
        }
    }

    static func continuing(_ count: Int) -> [HomeViewModel.ContinueEntry] {
        (0..<count).map { index in
            let id = SeriesRecord.ID(rawValue: Int64(index + 1))
            let read: Date = .now.addingTimeInterval(TimeInterval(-index * 3_600))
            return HomeViewModel.ContinueEntry(
                id: id,
                title: title(index),
                cover: nil,
                unreadCount: index * 3,
                lastReadDate: read,
                target: target(index)
            )
        }
    }

    static func added(_ count: Int) -> [HomeViewModel.AddedEntry] {
        (0..<count).map { index in
            let id = SeriesRecord.ID(rawValue: Int64(100 + index))
            let unread: Int = index.isMultiple(of: 3) ? 0 : index * 7
            return HomeViewModel.AddedEntry(
                id: id,
                title: title(index + 3),
                cover: nil,
                unreadCount: unread,
                addedDate: .now.addingTimeInterval(TimeInterval(-index * 86_400))
            )
        }
    }

    static func sessions(_ count: Int) -> [ReadingSessionEntry] {
        (0..<count).map { index in
            let started: Date = .now.addingTimeInterval(TimeInterval(-index * 7_200))
            let ended: Date = started.addingTimeInterval(TimeInterval(900 + index * 300))
            return ReadingSessionEntry(
                id: Int64(index + 1),
                seriesId: Int64(index + 1),
                seriesTitle: title(index + 1),
                pagesRead: 18 + index * 4,
                chaptersRead: index.isMultiple(of: 2) ? 1 : 0,
                startedDate: started,
                endedDate: ended,
                localDayKey: started.localDayKey,
                alive: index != 3
            )
        }
    }

    static func snapshot(
        continuing count: Int = 4,
        added addedCount: Int = 8,
        sessions sessionCount: Int = 5,
        stats tiles: HomeViewModel.StatTiles = stats
    ) -> HomeViewModel.Snapshot {
        HomeViewModel.Snapshot(
            continueReading: continuing(count),
            recentlyAdded: added(addedCount),
            sessions: sessions(sessionCount),
            stats: tiles
        )
    }
}

#Preview("Content") {
    HomeScreen(vm: .preview(snapshot: Mock.snapshot()))
}

// the whole strip hides when every number is zero - absence is the signal, and
// a fresh library should not be greeted with a row of noughts
#Preview("No Activity Yet") {
    HomeScreen(
        vm: .preview(
            snapshot: Mock.snapshot(sessions: 0, stats: .init(chaptersInRange: 0, secondsInRange: 0, currentRun: 0))
        )
    )
}

#Preview("All Time") {
    HomeScreen(
        vm: .preview(
            snapshot: Mock.snapshot(stats: .init(chaptersInRange: 1_284, secondsInRange: 512_000, currentRun: 3)),
            range: .all
        )
    )
}

#Preview("Continue Only") {
    HomeScreen(vm: .preview(snapshot: Mock.snapshot(continuing: 2, added: 0)))
}

#Preview("Empty") {
    HomeScreen(vm: .preview(snapshot: Mock.snapshot(continuing: 0, added: 0, sessions: 0)))
}

#Preview("Failed") {
    HomeScreen(
        vm: .preview(
            failure: Failure(
                title: "Couldn't Load Home",
                message: "Something unexpected went wrong. Please try again.",
                isRetryable: true
            )
        )
    )
}

#Preview("Loading") {
    HomeScreen(vm: .preview())
}
#endif

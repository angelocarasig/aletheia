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

    @AppStorage(Preferences.Key.blurAdultHome) private var blurAdult = Preferences.Default
        .blurAdultHome
    @AppStorage(Preferences.Key.bypassAdultSources) private var bypassAdult = Preferences.Default
        .bypassAdultSources

    @State private var vm: HomeViewModel?
    @State private var path = NavigationPath()
    @State private var reading: ReadingTarget?
    @State private var browsing = false
    @State private var showingUpdates = false
    @State private var showingFailures = false
    @State private var showingSettings = false

    init(vm: HomeViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private struct ReadingTarget: Identifiable, Hashable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID
        var id: ChapterRecord.ID { chapterId }
    }

    private enum Layout {
        static let addedColumns = 3
        static let skeletonUpdates = 3
        static let skeletonDots: CGFloat = 44
        static let skeletonDot: CGFloat = 6
        static let skeletonDotsRow: CGFloat = 32
        static let contentOffset: CGFloat = -20
        static let emptyFillOpacity = 0.05
    }

    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    // keyed on entries, not `obscured` - keying on the blur state would make
    // the toggle disappear the moment it's used
    private var hasExplicit: Bool {
        guard let snapshot = vm?.snapshot else { return false }
        return snapshot.continueReading.contains(where: \.adult)
            || snapshot.updates.contains(where: \.adult)
            || snapshot.recentlyAdded.contains(where: \.adult)
    }

    private var hasHero: Bool {
        phase == .content && !(vm?.continueReading.isEmpty ?? true)
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil {
                .failed
            } else if vm.snapshot == nil {
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
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "person.crop.circle")
                        .tappable { showingSettings = true }
                        .accessibilityLabel("Settings")
                }

                if hasExplicit {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)

                    ToolbarItem(placement: .topBarTrailing) {
                        BlurToggle(
                            isOn: !obscured,
                            label: "Adult content",
                            action: { blurAdult = blurAdult.toggled(adultSource: false) }
                        )
                    }
                }
            }
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
            .navigationDestination(item: $reading) { target in
                ReaderScreen(seriesId: target.seriesId, chapterId: target.chapterId)
            }
            .navigationDestination(isPresented: $browsing) {
                SearchScreen(query: "", embedded: true)
            }
            .navigationDestination(isPresented: $showingUpdates) {
                UpdatesScreen()
            }
            .navigationDestination(isPresented: $showingFailures) {
                FailuresScreen()
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsScreen()
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
            // task(id:) would also refire on every return to this tab, restarting
            // an observation that's already correct
            .onChange(of: bypassAdult) { vm?.retry() }
        }
    }
}

// MARK: - Content

extension HomeScreen {
    fileprivate func Content(_ vm: HomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                let continueReading = vm.continueReading
                if !continueReading.isEmpty {
                    HeroCarousel(
                        entries: continueReading,
                        obscured: obscured,
                        onContinue: { entry in
                            reading = ReadingTarget(
                                seriesId: entry.id, chapterId: entry.target.chapterId)
                        },
                        onDetails: { entry in
                            path.append(SeriesEntry.library(entry.id))
                        }
                    )
                }

                Group {
                    let failing = vm.failingSources
                    if failing > 0 {
                        FailingBanner(failing)
                    }

                    let unsynced = vm.failingTrackers
                    if unsynced > 0 {
                        StalledBanner(unsynced)
                    }

                    let added = vm.recentlyAdded
                    let settled = !added.isEmpty

                    if continueReading.isEmpty, settled {
                        ContinueEmpty
                    }

                    let updates = vm.updates
                    if !updates.isEmpty {
                        UpdatesSection(updates)
                    } else if settled {
                        UpdatesEmpty
                    }

                    if !added.isEmpty {
                        AddedSection(entries: added)
                    }

                    let stalled = vm.stalled
                    if !stalled.isEmpty {
                        ShelfSection(
                            title: "Pick Back Up",
                            entries: stalled,
                            detail: Self.position,
                            accessory: { _ in nil }
                        )
                    }

                    let waiting = vm.waiting
                    if !waiting.isEmpty {
                        ShelfSection(
                            title: "Waiting For You",
                            entries: waiting,
                            detail: Self.next,
                            accessory: { Text("\($0.unreadCount)") }
                        )
                    }
                }
                .offset(y: hasHero ? Layout.contentOffset : 0)
            }
            .padding(.bottom, dimensions.spacing.space16)
            .padding(.top, hasHero ? 0 : dimensions.spacing.space16)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: hasHero ? .top : [])
    }

    fileprivate var ContinueEmpty: some View {
        Section(
            title: "Continue Reading",
            message: "Open something from your library and it will wait for you here."
        )
    }

    fileprivate var UpdatesEmpty: some View {
        Section(
            title: "New Chapters",
            message: "New chapters from your sources land here after a refresh."
        )
    }

    // ContentUnavailableView sizes for a full screen; this is a row-sized
    // empty state inside an otherwise populated screen
    fileprivate func Section(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader(title)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(dimensions.spacing.space12)
                .background(
                    .primary.opacity(Layout.emptyFillOpacity),
                    in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
                )
        }
        .padding(.horizontal, dimensions.screenMargin)
    }

    fileprivate func UpdatesSection(_ updates: [HomeViewModel.UpdateEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("New Chapters")

            GlassEffectContainer(spacing: dimensions.spacing.space12) {
                VStack(spacing: dimensions.spacing.space12) {
                    ForEach(updates) { entry in
                        UpdateCard(
                            title: entry.title,
                            cover: entry.cover,
                            count: entry.count,
                            latest: entry.latest,
                            obscured: obscured && entry.adult
                        )
                        .contentShape(.rect)
                        .tappable {
                            path.append(SeriesEntry.library(entry.id))
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
        .padding(.horizontal, dimensions.screenMargin)
    }

    fileprivate func FailingBanner(_ count: Int) -> some View {
        Banner(
            "^[\(count) source](inflect: true) couldn't update",
            message: "Series on them are missing new chapters",
            systemImage: "exclamationmark.triangle.fill",
            action: { showingFailures = true }
        )
        .padding(.horizontal, dimensions.screenMargin)
        .accessibilityHint("Opens the list of sources needing attention")
    }

    fileprivate func StalledBanner(_ count: Int) -> some View {
        Banner(
            "^[\(count) series](inflect: true) isn't syncing",
            message: "Your progress hasn't reached the tracker yet",
            systemImage: "app.connected.to.app.below.fill",
            action: { showingFailures = true }
        )
        .padding(.horizontal, dimensions.screenMargin)
        .accessibilityHint("Opens the list of failures")
    }

    fileprivate func ShelfSection(
        title: String,
        entries: [HomeViewModel.ShelfEntry],
        detail: @escaping (HomeViewModel.ShelfEntry) -> String,
        accessory: @escaping (HomeViewModel.ShelfEntry) -> Text?
    ) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader(title)

            VStack(spacing: dimensions.spacing.space8) {
                ForEach(entries) { entry in
                    ShelfRow(
                        title: entry.title,
                        cover: entry.cover,
                        detail: detail(entry),
                        accessory: accessory(entry),
                        obscured: obscured && entry.adult
                    )
                    .tappable {
                        path.append(SeriesEntry.library(entry.id))
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
        .padding(.horizontal, dimensions.screenMargin)
    }

    fileprivate nonisolated static func position(_ entry: HomeViewModel.ShelfEntry) -> String {
        guard case .resume(_, let number, let progress) = entry.target else {
            return "Partway through"
        }
        return "\(Int(progress * 100))% through \(ReadingFormat.chapter(number))"
    }

    fileprivate nonisolated static func next(_ entry: HomeViewModel.ShelfEntry) -> String {
        "Next up: \(ReadingFormat.chapter(entry.target.number))"
    }

    fileprivate func AddedSection(entries: [HomeViewModel.AddedEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Recently Added")
                .padding(.horizontal, dimensions.screenMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: dimensions.spacing.space12) {
                    ForEach(entries) { entry in
                        NavigationLink(value: SeriesEntry.library(entry.id)) {
                            AddedCard(
                                title: entry.title,
                                cover: entry.cover,
                                unreadCount: entry.unreadCount,
                                addedDate: entry.addedDate,
                                obscured: obscured && entry.adult
                            )
                            .containerRelativeFrame(
                                .horizontal,
                                count: Layout.addedColumns,
                                span: 1,
                                spacing: dimensions.spacing.space12
                            )
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .padding(.horizontal, dimensions.screenMargin)
            .scrollTargetBehavior(.viewAligned)
        }
    }

}

// MARK: - States

extension HomeScreen {
    fileprivate var Empty: some View {
        ContentUnavailableView {
            Label("Nothing to Read Yet", systemImage: "book.closed")
        } description: {
            Text("Series you read and add to your library will appear here.")
        } actions: {
            Button("Find Series") { browsing = true }
                .buttonStyle(.borderedProminent)
        }
    }

    fileprivate func Unavailable(_ failure: Failure) -> some View {
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

    fileprivate var Skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: dimensions.radius.radius20, style: .continuous)
                        .fill(.primary.opacity(Layout.emptyFillOpacity))
                        .frame(height: HeroCard.panelHeight)
                        .padding(.vertical, dimensions.spacing.space16)

                    Capsule()
                        .fill(.primary.opacity(Layout.emptyFillOpacity))
                        .frame(width: Layout.skeletonDots, height: Layout.skeletonDot)
                        .frame(height: Layout.skeletonDotsRow)
                        .offset(y: Layout.contentOffset)
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("New Chapters")

                    VStack(spacing: dimensions.spacing.space16) {
                        ForEach(0..<Layout.skeletonUpdates, id: \.self) { _ in
                            UpdateCard(title: "", cover: nil, count: 0, latest: .distantPast)
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
            "Tower of Ash",
        ]

        static func title(_ index: Int) -> String {
            titles[index % titles.count]
        }

        static let cover = URL(
            string: "https://mangadex.org/covers"
                + "/e9d69f82-4c53-44ce-a94b-32303d172227"
                + "/6fc27968-9405-443d-9e2c-a094c06324cd.jpg.512.jpg"
        )

        static func read(_ index: Int) -> Double {
            Double(20 + index * 13)
        }

        static func target(_ index: Int) -> ContinueTarget {
            let id = ChapterRecord.ID(rawValue: Int64(index + 1))
            if index.isMultiple(of: 2) {
                return .resume(chapterId: id, number: read(index), progress: 0.45)
            } else {
                return .start(chapterId: id, number: read(index) + 1)
            }
        }

        static func continuing(_ count: Int) -> [HomeViewModel.ContinueEntry] {
            (0..<count).map { index in
                let id = SeriesRecord.ID(rawValue: Int64(index + 1))
                let lastRead: Date = .now.addingTimeInterval(TimeInterval(-index * 3_600))
                return HomeViewModel.ContinueEntry(
                    id: id,
                    title: title(index),
                    cover: cover,
                    unreadCount: index * 3,
                    lastReadDate: lastRead,
                    target: target(index),
                    adult: index.isMultiple(of: 4),
                    authors: index == 2 ? nil : "Yuna Seo, Haneul Park, Jiwoo Lim",
                    publication: [.Ongoing, .Hiatus, .Completed][index % 3],
                    totalChapters: 60 + index * 40,
                    lastReadNumber: read(index)
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
                    addedDate: .now.addingTimeInterval(TimeInterval(-index * 86_400)),
                    adult: index.isMultiple(of: 4)
                )
            }
        }

        static func updates(_ count: Int) -> [HomeViewModel.UpdateEntry] {
            (0..<count).map { index in
                let id = SeriesRecord.ID(rawValue: Int64(200 + index))
                return HomeViewModel.UpdateEntry(
                    id: id,
                    title: title(index + 1),
                    cover: nil,
                    count: [3, 1, 12, 2, 7][index % 5],
                    latest: .now.addingTimeInterval(TimeInterval(-index * 5_400)),
                    target: target(index),
                    adult: index.isMultiple(of: 4)
                )
            }
        }

        static func shelf(_ count: Int, resuming: Bool) -> [HomeViewModel.ShelfEntry] {
            (0..<count).map { index in
                let chapter = ChapterRecord.ID(rawValue: Int64(900 + index))
                let target: ContinueTarget =
                    resuming
                    ? .resume(
                        chapterId: chapter, number: Double(40 + index),
                        progress: Double(20 + index * 17) / 100)
                    : .start(chapterId: chapter, number: Double(112 + index * 3))
                let unread: Int = resuming ? index : (index + 1) * 7

                return HomeViewModel.ShelfEntry(
                    id: SeriesRecord.ID(rawValue: Int64(500 + index)),
                    title: titles[(index + 3) % titles.count],
                    unreadCount: unread,
                    target: target,
                    adult: index.isMultiple(of: 4)
                )
            }
        }

        static func snapshot(
            continuing count: Int = 4,
            added addedCount: Int = 8,
            updates updateCount: Int = 5,
            stalled stalledCount: Int = 3,
            waiting waitingCount: Int = 4,
            failing: Int = 0
        ) -> HomeViewModel.Snapshot {
            HomeViewModel.Snapshot(
                continueReading: continuing(count),
                updates: updates(updateCount),
                recentlyAdded: added(addedCount),
                stalled: shelf(stalledCount, resuming: true),
                waiting: shelf(waitingCount, resuming: false),
                failingSources: failing
            )
        }
    }

    #Preview("Content") {
        HomeScreen(vm: .preview(snapshot: Mock.snapshot()))
    }

    #Preview("Nothing Waiting") {
        HomeScreen(vm: .preview(snapshot: Mock.snapshot(updates: 0)))
    }

    #Preview("Shelves") {
        HomeScreen(
            vm: .preview(
                snapshot: Mock.snapshot(continuing: 1, added: 2, updates: 0, stalled: 4, waiting: 4)
            ))
    }

    #Preview("Caught Up") {
        HomeScreen(vm: .preview(snapshot: Mock.snapshot(stalled: 0, waiting: 0)))
    }

    #Preview("Sources Failing") {
        HomeScreen(vm: .preview(snapshot: Mock.snapshot(failing: 3)))
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

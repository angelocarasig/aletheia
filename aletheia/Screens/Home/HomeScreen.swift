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

    @AppStorage(Preferences.Key.blurAdultHome) private var blurAdult = Preferences.Default.blurAdultHome
    // read only to notice it changing: the gate itself is resolved inside the
    // observation, and the ten-tap that flips it happens on another tab
    @AppStorage(Preferences.Key.bypassAdultSources) private var bypassAdult = Preferences.Default.bypassAdultSources

    @State private var vm: HomeViewModel?
    @State private var path = NavigationPath()
    @State private var reading: ReadingTarget?
    @State private var browsing = false
    @State private var showingUpdates = false
    @State private var showingFailures = false
    @State private var showingSettings = false

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
        static let addedWidth: CGFloat = 116
        static let skeletonUpdates = 3
        static let heroSpan = 8

        // quieter than the banner - an unearned section is a fact about where
        // the reader is, not something asking to be looked at
        static let emptyFillOpacity = 0.05
    }

    // home is what you already own, so there is no "did you ask for this" signal
    // the way opening an adult source is one - unset covers
    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    // absent unless a rail actually holds one - a reveal with nothing to reveal
    // is a control with nothing to say. keyed on the entries rather than on
    // whether they are currently blurred, or using it would remove it
    private var hasExplicit: Bool {
        guard let snapshot = vm?.snapshot else { return false }
        return snapshot.continueReading.contains(where: \.adult)
            || snapshot.updates.contains(where: \.adult)
            || snapshot.recentlyAdded.contains(where: \.adult)
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
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                // a person, not a gear. the app had four gearshapes meaning four
                // different scopes - the whole app, one tab's refresh cadence,
                // one source, one reading session - and a reader who taps one
                // and gets a scope they did not expect stops trusting the glyph.
                // this destination holds the tracker accounts, which is what
                // makes a person the honest mark for it: gear now only ever
                // means "this thing here", and the person means "you, and
                // everything"
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "person.crop.circle")
                        .tappable { showingSettings = true }
                        .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if hasExplicit {
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
            // onChange rather than task(id:), which would also fire on every
            // return to the tab and restart an observation that is already right
            .onChange(of: bypassAdult) { vm?.retry() }
        }
    }
}

// MARK: - Content

private extension HomeScreen {
    func Content(_ vm: HomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                // its presence is the whole signal, so it costs nothing at rest
                // and is unmissable when it fires. a permanent card reading
                // "all sources healthy" would train the eye to skip the one
                // place that matters
                let failing = vm.failingSources
                if failing > 0 {
                    FailingBanner(failing)
                }

                // its own banner rather than a combined count: the two are
                // different units and different costs. a dead source loses you
                // chapters, a stalled tracker loses you a number on someone
                // else's website, and one sentence covering both would have to
                // stop saying either
                let unsynced = vm.failingTrackers
                if unsynced > 0 {
                    StalledBanner(unsynced)
                }

                // once there is a library at all, an absent section is more
                // confusing than an empty one: the reader who added three
                // series and read none got a screen with a single rail on it
                // and no way to tell whether the rest was broken or unearned.
                // held to a compact row rather than a screen-sized empty, or
                // two of them would push the only real content off the fold
                let added = vm.recentlyAdded
                let settled = !added.isEmpty

                // resume before news: five of six readers went straight for
                // this and stopped, and the one returning after a gap asked to
                // be put back in the story rather than in front of a ledger
                let continueReading = vm.continueReading
                if !continueReading.isEmpty {
                    ContinueSection(vm, entries: continueReading)
                } else if settled {
                    ContinueEmpty
                }

                // the section the screen was missing, and the reason every
                // comparable app lands on one: open, see what arrived, tap it
                let updates = vm.updates
                if !updates.isEmpty {
                    UpdatesSection(updates)
                } else if settled {
                    UpdatesEmpty
                }

                // demoted from a two-column grid to a rail: it is a log of your
                // own actions, so it earns a shelf and not a screenful
                if !added.isEmpty {
                    AddedSection(entries: added)
                }

                // the two shelves. they are a partition of everything that fell
                // out of the rail's window, split by where the reader stopped:
                // inside a chapter, or cleanly at the end of one. no series is on
                // both, and neither is in the rail
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
                        // the pile is the whole point of this shelf, so it is the
                        // one number that gets its own mark
                        accessory: { Text("\($0.unreadCount)") }
                    )
                }
            }
            .padding(.vertical, dimensions.spacing.space16)
        }
        // the rails inside already scroll and show their own edges, so the outer
        // bar is a second scrollbar describing a different axis of the same view
        .scrollIndicators(.hidden)
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
                            target: entry.target,
                            obscured: obscured && entry.adult
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


    // no action any more: Reading Activity moved into the Activity tab on
    // 2026-08-11, and a Home shortcut to a tab is the one link this screen has
    // always refused to carry
    var ContinueEmpty: some View {
        Section(
            title: "Continue Reading",
            message: "Open something from your library and it will wait for you here."
        )
    }

    var UpdatesEmpty: some View {
        Section(
            title: "New Chapters",
            message: "New chapters from your sources land here after a refresh."
        )
    }

    // one row's worth, not a screen's worth: ContentUnavailableView sizes
    // itself for an empty screen, and nothing here is empty except this shelf
    // no action parameter any more: both destinations this screen used to offer
    // are gone - Reading Activity moved into the Activity tab, and the updates
    // list with it - so a section is a title and a sentence
    func Section(title: String, message: String) -> some View {
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

    // tiles only - the numbers' rows live one tap deeper, and the whole strip
    // is that tap. record-framed: a run is a fact, never a countdown. the window
    // is named once, in the subtitle, rather than on every label
    func UpdatesSection(_ updates: [HomeViewModel.UpdateEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("New Chapters")

            // grouped so the surfaces blend into each other rather than reading
            // as four unrelated panes
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
                        // opens the chapter, not a screen about the chapter -
                        // the same resolver Continue Reading taps through
                        .tappable {
                            reading = ReadingTarget(seriesId: entry.id, chapterId: entry.target.chapterId)
                        }
                        .contextMenu {
                            Button {
                                path.append(SeriesEntry.library(entry.id))
                            } label: {
                                Label("View Series", systemImage: "book")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, dimensions.screenMargin)
    }

    // "couldn't update" names what happened and to what. a bare status word
    // carries no subject, and both a new reader and one returning after a gap
    // read it as their own fault
    func FailingBanner(_ count: Int) -> some View {
        Banner(
            "^[\(count) source](inflect: true) couldn't update",
            message: "Series on them are missing new chapters",
            systemImage: "exclamationmark.triangle.fill",
            action: { showingFailures = true }
        )
        .padding(.horizontal, dimensions.screenMargin)
        // the banner combines its own children, so the hint lands on the one
        // element they became. the label it would otherwise get is the title
        // and the message read in order, which is what a reader wants here
        .accessibilityHint("Opens the list of sources needing attention")
    }

    // "isn't reaching" rather than "failed": nothing here is lost, the push is
    // still queued, and the reader's own read state is untouched
    func StalledBanner(_ count: Int) -> some View {
        Banner(
            "^[\(count) series](inflect: true) isn't syncing",
            message: "Your progress hasn't reached the tracker yet",
            systemImage: "app.connected.to.app.below.fill",
            action: { showingFailures = true }
        )
        .padding(.horizontal, dimensions.screenMargin)
        .accessibilityHint("Opens the list of failures")
    }

    // a glass circle, not a bare chevron. the arrow that used to carry this was
    // a 13pt glyph parked at the far screen edge from the words it belonged to,
    // with nothing behind it, and nobody found it - what makes this readable as
    // a control is the surface, which is the same thing that makes the chart's
    // stepper readable. the glyph says which of the two it is
    // one builder for both shelves: they differ by their second line and whether
    // they carry a count, and a second hand-written copy would drift the moment
    // one of them is touched
    func ShelfSection(
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
                        reading = ReadingTarget(seriesId: entry.id, chapterId: entry.target.chapterId)
                    }
                    .contextMenu {
                        NavigationLink(value: SeriesEntry.library(entry.id)) {
                            Label("View Series", systemImage: "book")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, dimensions.screenMargin)
    }

    // where you are, not how long you have been away. a duration reads as
    // neglect and a position reads as a place to stand, which is the difference
    // between a shelf a reader uses and one they scroll past
    static func position(_ entry: HomeViewModel.ShelfEntry) -> String {
        guard case let .resume(_, number, progress) = entry.target else {
            return "Partway through"
        }
        return "\(Int(progress * 100))% through \(ReadingFormat.chapter(number))"
    }

    static func next(_ entry: HomeViewModel.ShelfEntry) -> String {
        "Next up: \(ReadingFormat.chapter(entry.target.number))"
    }

    // a rail rather than the two-column grid it was: this is a log of what you
    // added, which is the Library's default sort with a caption on it, and a
    // grid of it was the largest block on the screen for the least news
    func AddedSection(entries: [HomeViewModel.AddedEntry]) -> some View {
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
                            .frame(width: Layout.addedWidth)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, dimensions.screenMargin)
            }
            .scrollTargetBehavior(.viewAligned)
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
        "Tower of Ash"
    ]

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
                target: target(index),
                adult: index.isMultiple(of: 4)
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
                // a spread rather than a constant: one new chapter and twelve
                // are different news, and the row has to hold both
                count: [3, 1, 12, 2, 7][index % 5],
                latest: .now.addingTimeInterval(TimeInterval(-index * 5_400)),
                target: target(index),
                adult: index.isMultiple(of: 4)
            )
        }
    }

    // the two shelves, built from the same titles so a preview reads as one
    // library rather than three unrelated ones
    static func shelf(_ count: Int, resuming: Bool) -> [HomeViewModel.ShelfEntry] {
        (0..<count).map { index in
            let chapter = ChapterRecord.ID(rawValue: Int64(900 + index))
            let target: ContinueTarget = resuming
                ? .resume(chapterId: chapter, number: Double(40 + index), progress: Double(20 + index * 17) / 100)
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

// nothing new anywhere: the updates block goes rather than rendering a header
// over an empty list, and Continue Reading carries the screen
#Preview("Nothing Waiting") {
    HomeScreen(vm: .preview(snapshot: Mock.snapshot(updates: 0)))
}

// absent entirely when nothing is failing, which is what lets it be loud when
// it is not: a notice that is always on screen is one nobody reads
// the two shelves alone, at their caps, which is where the page first has to
// justify scrolling past the rails
#Preview("Shelves") {
    HomeScreen(vm: .preview(snapshot: Mock.snapshot(continuing: 1, added: 2, updates: 0, stalled: 4, waiting: 4)))
}

// neither shelf has anything: a caught-up library, where both sections are
// absent rather than empty
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

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
    @State private var showingStats = false
    @State private var showingUpdates = false
    @State private var showingFailures = false

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

        // enough to lift the banner off the canvas without competing with a
        // cover: it is a notice, not an alert
        static let bannerFill = 0.12
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
            .navigationDestination(isPresented: $showingStats) {
                StatsScreen()
            }
            .navigationDestination(isPresented: $showingUpdates) {
                UpdatesScreen()
            }
            .navigationDestination(isPresented: $showingFailures) {
                FailuresScreen()
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

                // resume before news: five of six readers went straight for
                // this and stopped, and the one returning after a gap asked to
                // be put back in the story rather than in front of a ledger
                let continueReading = vm.continueReading
                if !continueReading.isEmpty {
                    ContinueSection(vm, entries: continueReading)
                }

                // the section the screen was missing, and the reason every
                // comparable app lands on one: open, see what arrived, tap it
                let updates = vm.updates
                if !updates.isEmpty {
                    UpdatesSection(updates)
                }

                // demoted from a two-column grid to a rail: it is a log of your
                // own actions, so it earns a shelf and not a screenful
                let added = vm.recentlyAdded
                if !added.isEmpty {
                    AddedSection(entries: added)
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
            SectionHeader(title: "Continue Reading") {
                Action("chart.bar.xaxis", label: "Reading Activity") { showingStats = true }
            }
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


    // tiles only - the numbers' rows live one tap deeper, and the whole strip
    // is that tap. record-framed: a run is a fact, never a countdown. the window
    // is named once, in the subtitle, rather than on every label
    func UpdatesSection(_ updates: [HomeViewModel.UpdateEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader(title: "New Chapters") {
                Action("list.bullet", label: "All Updates") { showingUpdates = true }
            }

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
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Palette.warningText)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("^[\(count) source](inflect: true) couldn't update")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Series on them are missing new chapters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .background(Palette.warningText.opacity(Layout.bannerFill), in: .rect(cornerRadius: dimensions.radius.radius12))
        .padding(.horizontal, dimensions.screenMargin)
        .contentShape(.rect)
        .tappable { showingFailures = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("^[\(count) source](inflect: true) couldn't update")
        .accessibilityHint("Opens the list of sources needing attention")
    }

    // a glass circle, not a bare chevron. the arrow that used to carry this was
    // a 13pt glyph parked at the far screen edge from the words it belonged to,
    // with nothing behind it, and nobody found it - what makes this readable as
    // a control is the surface, which is the same thing that makes the chart's
    // stepper readable. the glyph says which of the two it is
    func Action(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: glyph)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
            .tappable(action: action)
            .accessibilityLabel(label)
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

    static func snapshot(
        continuing count: Int = 4,
        added addedCount: Int = 8,
        updates updateCount: Int = 5,
        failing: Int = 0
    ) -> HomeViewModel.Snapshot {
        HomeViewModel.Snapshot(
            continueReading: continuing(count),
            updates: updates(updateCount),
            recentlyAdded: added(addedCount),
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

//
//  LibraryScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import Tagged

struct LibraryScreen: View {
    @Environment(\.database) private var database
    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor

    @AppStorage(Preferences.Key.gridColumns) private var gridColumns = Preferences.Default
        .gridColumns
    @AppStorage(Preferences.Key.blurAdultLibrary) private var blurAdult = Preferences.Default
        .blurAdultLibrary
    @AppStorage(Preferences.Key.bypassAdultSources) private var bypassAdult = Preferences.Default
        .bypassAdultSources
    @State private var vm: LibraryViewModel?
    @State private var showingCollectionForm = false
    @State private var showingSort = false
    @State private var showingFilters = false
    @State private var actionsExpanded = false
    // updated as each section's header appears on screen - the hopper's
    // previous/next targets are computed off this, not a separate selection
    @State private var activeSectionID: LibraryViewModel.SectionID?
    @State private var confirmingLibraryRefresh = false
    @State private var confirmingSectionRefresh: LibraryViewModel.Section?

    private enum Layout {
        static let placeholderCards = 12
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: dimensions.spacing.space12),
            count: max(1, gridColumns)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // not lazy - a lazy stack would tear the grid -> no-matches swap out
                    // instead of transitioning it
                    VStack(spacing: dimensions.spacing.space16) {
                        if let vm {
                            Searchbar(
                                searchText: Binding(
                                    get: { vm.searchText }, set: { vm.searchText = $0 }),
                                placeholder: "Search Your Library",
                                handoff: .init(
                                    tint: .brand,
                                    label: { "Search every source for \"\($0)\"" },
                                    onSelect: { text in log("handoff to sources - \(text)") }
                                )
                            )
                            .padding(.horizontal, dimensions.screenMargin)
                        }

                        Content
                    }
                    .padding(.top, dimensions.spacing.space8)
                    .animation(.settle, value: phase)
                }
                // the confirm gate, not the refresh itself - always whole-library
                // since sections are no longer exclusive views, so there is no
                // single collection left to scope a pull-to-refresh to
                .refreshable {
                    confirmingLibraryRefresh = true
                }
                .alert("Refresh Library?", isPresented: $confirmingLibraryRefresh) {
                    Button("Refresh") { compositor.refresh.start() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("^[\(vm?.entries.count ?? 0) series](inflect: true) will be refreshed.")
                }
                .alert(
                    "Refresh \(confirmingSectionRefresh?.name ?? "")?",
                    isPresented: Binding(
                        get: { confirmingSectionRefresh != nil },
                        set: { if !$0 { confirmingSectionRefresh = nil } }
                    ),
                    presenting: confirmingSectionRefresh
                ) { section in
                    Button("Refresh") {
                        compositor.refresh.start(
                            series: Set(section.entries.map(\.id)), named: section.name)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { section in
                    Text("^[\(section.entries.count) series](inflect: true) in \(section.name) will be refreshed.")
                }
                // before .safeAreaBar so that bar draws above this overlay -
                // reordering would make the actions cluster's own controls untappable
                .overlay {
                    if actionsExpanded {
                        Dismisser
                    }
                }
                // safeAreaBar rather than overlay+padding - it registers as a control
                // surface so the scroll edge effect reaches it, and reserves clearance
                // for the last row
                .safeAreaBar(edge: .bottom) {
                    ZStack(alignment: .bottom) {
                        if let vm {
                            LibraryCategoryHopper(
                                sections: vm.sections,
                                activeID: activeSectionID,
                                onJump: { id in
                                    withAnimation(.smooth) { proxy.scrollTo(id, anchor: .top) }
                                },
                                onCreate: { showingCollectionForm = true }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        LibraryActions(
                            onSort: { showingSort = true },
                            onFilter: { showingFilters = true },
                            filtered: vm?.filter.isActive ?? false,
                            expanded: $actionsExpanded
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, dimensions.screenMargin)
                    .padding(.bottom, dimensions.spacing.space16)
                }
                .navigationTitle("Library")
                .navigationSubtitle(subtitle)
            .toolbarTitleDisplayMode(.large)
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
            // no settings entry point here - refresh cadence already lives in
            // Settings, and a gear here was mistaken for it by test readers
            // before being removed
            .toolbar {
                // shown only when something could be covered - if this were keyed
                // on `obscured` instead of the raw classification, toggling it
                // would remove itself
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
            .sheet(isPresented: $showingSort) {
                if let vm {
                    LibrarySortSheet(
                        sort: Binding(get: { vm.sort }, set: { vm.sort = $0 }),
                        ascending: Binding(get: { vm.ascending }, set: { vm.ascending = $0 })
                    )
                }
            }
            .sheet(isPresented: $showingFilters) {
                if let vm {
                    LibraryFilterSheet(
                        filter: Binding(get: { vm.filter }, set: { vm.filter = $0 }),
                        tags: vm.tags,
                        sources: vm.sources,
                        trackers: vm.trackers
                    )
                }
            }
            .sheet(isPresented: $showingCollectionForm) {
                if let vm {
                    CollectionForm(isSaving: vm.isSaving) { name, description in
                        Task { await vm.createCollection(name: name, description: description) }
                    }
                }
            }
            .task {
                let vm =
                    vm
                    ?? LibraryViewModel(
                        database: database,
                        assets: compositor.assets,
                        registry: compositor.registry
                    )
                self.vm = vm
                await vm.load()
            }
            // task(id:) cancels the prior task on each keystroke - no separate
            // debounce needed
            .task(id: vm?.searchText) {
                await vm?.search()
            }
            // onChange rather than task(id:) - task(id:) also fires on every
            // return to this tab, reloading a grid that's already correct
            .onChange(of: bypassAdult) {
                Task { await vm?.load() }
            }
            }
        }
    }

    private var subtitle: Text {
        guard let vm, !vm.isLoading, !vm.entries.isEmpty else { return Text("") }
        return Text("^[\(vm.filtered.count) series](inflect: true)")
    }
}

// MARK: - Chrome

extension LibraryScreen {
    // zero-distance DragGesture, not onTapGesture - onTapGesture fires on
    // release, so a drag that lands here and lifts elsewhere would leave the
    // panel open
    fileprivate var Dismisser: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { _ in
                    guard actionsExpanded else { return }
                    withAnimation(.smooth) { actionsExpanded = false }
                }
            )
            .accessibilityHidden(true)
    }

    // queued is read unconditionally even though it's only used when checking is
    // false - short-circuiting it would stop this from redrawing when a series
    // moves from queued to checking under Observation
    fileprivate func activity(for id: SeriesRecord.ID) -> LibraryCard.Activity? {
        let refresh = compositor.refresh
        let checking = refresh.isChecking(series: id.rawValue)
        let queued = refresh.isQueued(series: id.rawValue)

        if checking { return .checking }
        return queued ? .queued : nil
    }

    fileprivate func log(_ message: String) {
        AppLog.shared.log("TODO \(message)", level: .warning, category: "library")
    }
}

// MARK: - Content

extension LibraryScreen {
    fileprivate var phase: LoadPhase {
        if vm?.failure != nil {
            .failed
        } else if vm == nil || vm?.isLoading == true {
            .pending
        } else if vm?.sections.isEmpty == true {
            .empty
        } else {
            .content
        }
    }

    @ViewBuilder
    fileprivate var Content: some View {
        switch phase {
        case .failed:
            if let vm, let failure = vm.failure {
                Failed(failure)
                    .transition(.opacity)
            }
        case .pending:
            Skeleton
                .transition(.opacity)
        case .empty:
            if let vm {
                Empty(vm)
                    .transition(.opacity)
            }
        case .content:
            if let vm {
                Grid(vm)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    fileprivate func Empty(_ vm: LibraryViewModel) -> some View {
        if vm.isFiltered {
            ContentUnavailableView {
                Label("No Matches", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Nothing in your library matches what you're looking for.")
            } actions: {
                Button("Clear Filters") {
                    withAnimation(.smooth) {
                        vm.searchText = ""
                        vm.filter.clear()
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("Library Empty", systemImage: "books.vertical")
            } description: {
                Text("Series you add from a source appear here.")
            } actions: {
                Button("Browse Sources") { log("browse sources") }
            }
        }
    }

    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    // reads off the filtered set, not entries - otherwise the toggle could offer
    // to reveal something already excluded by filters
    private var hasExplicit: Bool {
        vm?.filtered.contains { $0.classification == .Explicit } ?? false
    }

    @ViewBuilder
    fileprivate func Grid(_ vm: LibraryViewModel) -> some View {
        let sections = vm.sections

        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                        SectionHeader(section)

                        LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
                            ForEach(section.entries) { entry in
                                NavigationLink(value: SeriesEntry.library(entry.id)) {
                                    LibraryCard(
                                        title: entry.title,
                                        cover: entry.cover,
                                        unreadCount: entry.unreadCount,
                                        activity: activity(for: entry.id),
                                        obscured: obscured && entry.classification == .Explicit
                                    )
                                }
                                .buttonStyle(.plain)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                    }
                    // tagged on the whole section, not just the header text - the
                    // hopper scrolls to this id with anchor: .top, so the id has to
                    // sit at the section's actual top edge
                    .id(section.id)
                    // a coarse "which section is on screen" signal - fires as each
                    // section's block enters the viewport while scrolling, which is
                    // exactly what the hopper's previous/next needs to know
                    .onAppear { activeSectionID = section.id }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
        }
    }

    fileprivate func SectionHeader(_ section: LibraryViewModel.Section) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Text(section.name)
                .font(.headline)

            Text("\(section.entries.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Image(systemName: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .tappable { confirmingSectionRefresh = section }
        }
        .padding(.top, dimensions.spacing.space12)
        .padding(.bottom, dimensions.spacing.space4)
    }

    fileprivate func Failed(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        } actions: {
            if failure.isRetryable {
                Button("Try Again") {
                    Task { await vm?.load() }
                }
            }
        }
    }

    fileprivate var Skeleton: some View {
        LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
            ForEach(0..<Layout.placeholderCards, id: \.self) { _ in
                LibraryCard()
            }
        }
        .padding(.horizontal, dimensions.screenMargin)
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

// standalone mock, not LibraryScreen itself - the real screen's .task pulls a
// LibraryViewModel through @Environment(\.database)/(\.compositor), neither of
// which a plain preview provides. Section/Entry are plain structs though, so
// the sectioned-grid + header + hopper visuals can be mocked directly
#Preview("Library - Sectioned") {
    LibraryMockPreview()
}

private struct LibraryMockPreview: View {
    @Environment(\.dimensions) private var dimensions
    @State private var activeSectionID: LibraryViewModel.SectionID?
    @State private var actionsExpanded = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: dimensions.spacing.space12), count: 3)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                        ForEach(Self.sections) { section in
                            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                                HStack(spacing: dimensions.spacing.space12) {
                                    Text(section.name)
                                        .font(.headline)

                                    Text("\(section.entries.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()

                                    Spacer()

                                    Image(systemName: "arrow.clockwise")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .tappable {}
                                }
                                .padding(.top, dimensions.spacing.space12)
        .padding(.bottom, dimensions.spacing.space4)

                                LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
                                    ForEach(section.entries) { entry in
                                        LibraryCard(
                                            title: entry.title,
                                            cover: entry.cover,
                                            unreadCount: entry.unreadCount
                                        )
                                    }
                                }
                            }
                            .id(section.id)
                            .onAppear { activeSectionID = section.id }
                        }
                    }
                    .padding(.horizontal, dimensions.screenMargin)
                    .padding(.top, dimensions.spacing.space8)
                }
                .safeAreaBar(edge: .bottom) {
                    ZStack(alignment: .bottom) {
                        LibraryCategoryHopper(
                            sections: Self.sections,
                            activeID: activeSectionID,
                            onJump: { id in
                                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .top) }
                            },
                            onCreate: {}
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        LibraryActions(
                            onSort: {}, onFilter: {}, filtered: false, expanded: $actionsExpanded
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, dimensions.screenMargin)
                    .padding(.bottom, dimensions.spacing.space16)
                }
                .navigationTitle("Library")
            }
        }
    }

    private static func entry(_ title: String, unread: Int = 0) -> LibraryViewModel.Entry {
        LibraryViewModel.Entry(
            id: SeriesRecord.ID(rawValue: .random(in: 1...999_999)),
            title: title,
            cover: nil,
            unreadCount: unread,
            status: .reading,
            publication: .Ongoing,
            classification: .Safe,
            addedDate: .now,
            updatedDate: .now,
            lastReadDate: .now
        )
    }

    private static let sections: [LibraryViewModel.Section] = [
        Section(
            id: .uncategorized, name: "Uncategorized",
            entries: [
                entry("A Villain Consumed by Desire", unread: 3),
                entry("Serim's Golden Rule"),
                entry("Mistress Kanan is Devilishly Easy", unread: 12),
            ]),
        Section(
            id: .collection(CollectionRecord.ID(rawValue: 1)), name: "Favorites",
            entries: [
                entry("Solo Leveling", unread: 7),
                entry("Omniscient Reader"),
            ]),
        Section(
            id: .collection(CollectionRecord.ID(rawValue: 2)), name: "Completed",
            entries: [
                entry("The Beginning After the End"),
                entry("Return of the Mount Hua Sect", unread: 1),
                entry("Nano Machine"),
            ]),
    ]

    private typealias Section = LibraryViewModel.Section
}

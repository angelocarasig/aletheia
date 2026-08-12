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

    @AppStorage(Preferences.Key.gridColumns) private var gridColumns = Preferences.Default.gridColumns
    @AppStorage(Preferences.Key.blurAdultLibrary) private var blurAdult = Preferences.Default.blurAdultLibrary
    // read only to notice it changing: the gate itself is resolved inside load(),
    // and the ten-tap that flips it happens on another tab
    @AppStorage(Preferences.Key.bypassAdultSources) private var bypassAdult = Preferences.Default.bypassAdultSources
    @State private var vm: LibraryViewModel?
    @State private var showingCollectionForm = false
    @State private var showingSort = false
    @State private var showingFilters = false
    @State private var collectionsExpanded = false
    @State private var actionsExpanded = false

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
            ScrollView {
                // not lazy: a lazy stack tears children out instead of
                // transitioning them, so the grid -> no-matches swap cuts hard.
                // three children, and the grid inside does the real recycling
                VStack(spacing: dimensions.spacing.space16) {
                    if let vm {
                        Searchbar(
                            searchText: Binding(get: { vm.searchText }, set: { vm.searchText = $0 }),
                            placeholder: "Search Your Library",
                            // the library is what you already own, so the wider
                            // set is every source. same query, one step out
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
                // on the container that survives the swap, keyed to the same
                // value the branches switch on
                .animation(.settle, value: phase)
            }
            // returns as soon as the walk is under way rather than awaiting it:
            // a run is minutes, and holding the pull spinner open for that is
            // both a lie about what it means and a scroll view pinned down.
            // the cards mark themselves as they are checked, which is the
            // feedback the gesture actually earns
            .refreshable {
                guard let vm else { return }
                compositor.refresh.start(
                    collection: vm.selectedCollection,
                    named: vm.selectedCollection == nil ? nil : vm.title
                )
            }
            // before .safeAreaBar, so the bar is added by the outer modifier and
            // draws above this - the clusters' own controls stay tappable while
            // everything they are covering does not
            .overlay {
                if collectionsExpanded || actionsExpanded {
                    Dismisser
                }
            }
            // a bar rather than two overlays: it reserves the clearance the last
            // row needs instead of a literal bottom padding, and registers as a
            // control surface so the scroll edge effect reaches it
            //
            // stacked, not an HStack - the collections panel opens to full width,
            // which in a row would squeeze the actions cluster to nothing. one
            // cluster per corner, and only ever one of them open
            .safeAreaBar(edge: .bottom) {
                ZStack(alignment: .bottom) {
                    if let vm {
                        LibraryCollections(
                            collections: vm.collections,
                            total: vm.entries.count,
                            selected: selection(vm),
                            onCreate: { showingCollectionForm = true },
                            onRename: { _ in log("rename collection") },
                            onDelete: { _ in log("delete collection") },
                            expanded: $collectionsExpanded
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
                // the bar sits flush on the tab bar otherwise, and two glass
                // surfaces touching read as one
                .padding(.bottom, dimensions.spacing.space16)
            }
            // one cluster open at a time: opening either collapses the other
            .onChange(of: collectionsExpanded) { _, open in
                guard open else { return }
                withAnimation(.smooth) { actionsExpanded = false }
            }
            .onChange(of: actionsExpanded) { _, open in
                guard open else { return }
                withAnimation(.smooth) { collectionsExpanded = false }
            }
            // the title carries the collection, so the switcher does not have to
            .navigationTitle(vm?.title ?? "Library")
            .navigationSubtitle(subtitle)
            .toolbarTitleDisplayMode(.large)
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
            // what is in this toolbar changes what you are looking at. how often
            // the library refreshes does not, and it was already a row in
            // Settings - so the gear here was a second door into a furnished
            // room, and one that six readers in a row mistook for the app's own
            // settings before giving up on finding them
            .toolbar {
                // absent unless something on this screen could actually be
                // covered - a reveal with nothing to reveal is a control with
                // nothing to say. keyed on the entries rather than on whether
                // they are currently blurred, or using it would remove it
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
                let vm = vm ?? LibraryViewModel(
                    database: database,
                    assets: compositor.assets,
                    registry: compositor.registry
                )
                self.vm = vm
                await vm.load()
            }
            // keyed on the text, so swiftui cancels the in-flight query itself
            // when the next keystroke lands - no debounce clock to keep
            .task(id: vm?.searchText) {
                await vm?.search()
            }
            // onChange rather than task(id:), which would also fire on every
            // return to the tab and reload a grid that is already right
            .onChange(of: bypassAdult) {
                Task { await vm?.load() }
            }
        }
    }

    // the app's established count idiom, which until now only sheets used. counts
    // what is on screen, not what is owned - a filtered grid saying 40 while
    // showing 3 is the subtitle describing a different screen
    private var subtitle: Text {
        guard let vm, !vm.isLoading, !vm.entries.isEmpty else { return Text("") }
        return Text("^[\(vm.filtered.count) series](inflect: true)")
    }
}

// MARK: - Chrome

private extension LibraryScreen {
    // dismiss-on-touch-outside, the way a menu behaves. two things it is not:
    //
    // it is not an .onTapGesture, which fires on RELEASE - so a finger that
    // lands, drags and lifts elsewhere would leave the panel open, and the
    // panel would still be covering the thing being reached for. a zero-distance
    // DragGesture reports on touch DOWN, which is the moment the intent is
    // already legible.
    //
    // and it is not tinted. a scrim that darkens says "this is modal, the thing
    // behind it is unavailable", and the panel is neither - it is a clear
    // catcher whose only job is to spend the first touch
    var Dismisser: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { _ in
                    guard collectionsExpanded || actionsExpanded else { return }
                    withAnimation(.smooth) {
                        collectionsExpanded = false
                        actionsExpanded = false
                    }
                }
            )
            .accessibilityHidden(true)
    }

    // the switcher animates its own mutation, so this stays a plain passthrough
    func selection(_ vm: LibraryViewModel) -> Binding<CollectionRecord.ID?> {
        Binding(
            get: { vm.selectedCollection },
            set: { vm.selectedCollection = $0 }
        )
    }

    // both sets are read unconditionally rather than short-circuited: reading
    // one of them is what makes this card redraw when a run moves a series from
    // queued to checking, and a ternary that never touches `queued` would leave
    // waiting cards blank until something else invalidated them
    func activity(for id: SeriesRecord.ID) -> LibraryCard.Activity? {
        let refresh = compositor.refresh
        let checking = refresh.isChecking(series: id.rawValue)
        let queued = refresh.isQueued(series: id.rawValue)

        if checking { return .checking }
        return queued ? .queued : nil
    }

    func log(_ message: String) {
        AppLog.shared.log("TODO \(message)", level: .warning, category: "library")
    }
}

// MARK: - Content

private extension LibraryScreen {
    // branch selector and animation key are one value - see
    // docs/features/loading-transitions.md
    var phase: LoadPhase {
        if vm?.failure != nil { .failed }
        else if vm == nil || vm?.isLoading == true { .pending }
        else if vm?.filtered.isEmpty == true { .empty }
        else { .content }
    }

    @ViewBuilder
    var Content: some View {
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
    func Empty(_ vm: LibraryViewModel) -> some View {
        if vm.isFiltered {
            // distinct from an empty library: there is something to undo here
            ContentUnavailableView {
                Label("No Matches", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Nothing in your library matches what you're looking for.")
            } actions: {
                Button("Clear Filters") {
                    withAnimation(.smooth) {
                        vm.selectedCollection = nil
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

    // the library is what you own, so there is no "did you ask for this" signal
    // the way opening an adult source is one - unset covers
    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    // derived from Classification rather than a source's per-item flag, so this
    // is wider than a search stub's: Explicit folds erotica in with pornography.
    // read off the filtered set, or the control would offer to reveal something
    // the current filters have already taken off screen
    private var hasExplicit: Bool {
        vm?.filtered.contains { $0.classification == .Explicit } ?? false
    }

    @ViewBuilder
    func Grid(_ vm: LibraryViewModel) -> some View {
        let entries = vm.filtered

        if !entries.isEmpty {
            LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
                ForEach(entries) { entry in
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
                    // shrinking toward the card's own centre rather than sliding
                    // in from an edge: a grid cell has no edge to come from, and
                    // survivors are reflowing past it at the same time
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
        }
    }

    func Failed(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        } actions: {
            // only where trying again could actually change the answer
            if failure.isRetryable {
                Button("Try Again") {
                    Task { await vm?.load() }
                }
            }
        }
    }

    // one sweep across the whole grid rather than per card
    var Skeleton: some View {
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

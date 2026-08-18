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
            // fire-and-forget - awaiting the full run would pin the pull spinner
            // open for minutes; cards mark themselves as they're checked instead
            .refreshable {
                guard let vm else { return }
                compositor.refresh.start(
                    collection: vm.selectedCollection,
                    named: vm.selectedCollection == nil ? nil : vm.title
                )
            }
            // before .safeAreaBar so that bar draws above this overlay -
            // reordering would make the clusters' own controls untappable
            .overlay {
                if collectionsExpanded || actionsExpanded {
                    Dismisser
                }
            }
            // safeAreaBar rather than overlay+padding - it registers as a control
            // surface so the scroll edge effect reaches it, and reserves clearance
            // for the last row
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
                .padding(.bottom, dimensions.spacing.space16)
            }
            .onChange(of: collectionsExpanded) { _, open in
                guard open else { return }
                withAnimation(.smooth) { actionsExpanded = false }
            }
            .onChange(of: actionsExpanded) { _, open in
                guard open else { return }
                withAnimation(.smooth) { collectionsExpanded = false }
            }
            .navigationTitle(vm?.title ?? "Library")
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
                    guard collectionsExpanded || actionsExpanded else { return }
                    withAnimation(.smooth) {
                        collectionsExpanded = false
                        actionsExpanded = false
                    }
                }
            )
            .accessibilityHidden(true)
    }

    fileprivate func selection(_ vm: LibraryViewModel) -> Binding<CollectionRecord.ID?> {
        Binding(
            get: { vm.selectedCollection },
            set: { vm.selectedCollection = $0 }
        )
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
        } else if vm?.filtered.isEmpty == true {
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

    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    // reads off the filtered set, not entries - otherwise the toggle could offer
    // to reveal something already excluded by filters
    private var hasExplicit: Bool {
        vm?.filtered.contains { $0.classification == .Explicit } ?? false
    }

    @ViewBuilder
    fileprivate func Grid(_ vm: LibraryViewModel) -> some View {
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
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
        }
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

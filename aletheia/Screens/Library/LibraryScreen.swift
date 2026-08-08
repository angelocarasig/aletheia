//
//  LibraryScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct LibraryScreen: View {
    @Environment(\.database) private var database
    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor

    @AppStorage(Preferences.Key.gridColumns) private var gridColumns = Preferences.Default.gridColumns
    @State private var vm: LibraryViewModel?
    @State private var showingCollectionForm = false
    @State private var showingSort = false
    @State private var showingFilters = false

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
                                label: { "Search every source for “\($0)”" },
                                onSelect: { text in log("handoff to sources — \(text)") }
                            )
                        )
                        .padding(.horizontal, dimensions.screenMargin)
                    }

                    Content
                }
                .padding(.top, dimensions.spacing.space8)
                // the floating clusters overlap the scroll view, so the last row
                // needs somewhere to go once you reach the bottom
                .padding(.bottom, dimensions.spacing.space64)
            }
            // two clusters, one per corner: where you are on the left, what you
            // are doing to it on the right. separate containers on purpose - they
            // are unrelated controls that happen to share an edge
            .overlay(alignment: .bottomLeading) {
                if let vm {
                    LibraryCollections(
                        collections: vm.collections,
                        total: vm.entries.count,
                        selected: selection(vm),
                        onCreate: { showingCollectionForm = true },
                        onRename: { _ in log("rename collection") },
                        onDelete: { _ in log("delete collection") }
                    )
                    .padding(dimensions.screenMargin)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                LibraryActions(
                    onSort: { showingSort = true },
                    onFilter: { showingFilters = true },
                    filtered: vm?.filter.isActive ?? false
                )
                .padding(dimensions.screenMargin)
            }
            // the title carries the collection, so the switcher does not have to
            .navigationTitle(vm?.title ?? "Library")
            .navigationSubtitle(subtitle)
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
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
                        sources: vm.sources
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
    // the switcher animates its own mutation, so this stays a plain passthrough
    func selection(_ vm: LibraryViewModel) -> Binding<CollectionRecord.ID?> {
        Binding(
            get: { vm.selectedCollection },
            set: { vm.selectedCollection = $0 }
        )
    }

    func log(_ message: String) {
        AppLog.shared.log("TODO \(message)", category: "library")
    }
}

// MARK: - Content

private extension LibraryScreen {
    @ViewBuilder
    var Content: some View {
        if let vm, let failure = vm.failure {
            Failed(failure)
        } else if let vm, !vm.isLoading {
            Grid(vm)
        } else {
            Skeleton
        }
    }

    @ViewBuilder
    func Grid(_ vm: LibraryViewModel) -> some View {
        let entries = vm.filtered

        if entries.isEmpty, vm.isFiltered {
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
        } else if entries.isEmpty {
            ContentUnavailableView {
                Label("Library Empty", systemImage: "books.vertical")
            } description: {
                Text("Series you add from a source appear here.")
            } actions: {
                Button("Browse Sources") { log("browse sources") }
            }
        } else {
            LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
                ForEach(entries) { entry in
                    NavigationLink(value: SeriesEntry.library(entry.id)) {
                        LibraryCard(
                            title: entry.title,
                            cover: entry.cover,
                            unreadCount: entry.unreadCount
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
    }
}

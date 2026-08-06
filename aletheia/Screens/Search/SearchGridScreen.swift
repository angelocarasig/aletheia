//
//  SearchGridScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct SearchGridScreen: View {
    let source: Source

    @Environment(\.dimensions) private var dimensions
    @State private var vm: SearchGridViewModel
    @State private var showingRefine = false
    @State private var barHidden = false
    @State private var barHeight: CGFloat = 0
    @State private var safeTop: CGFloat = 0
    @State private var seriesRoute: SeriesStub?

    @AppStorage("gridColumns") private var gridColumns = 3

    private enum Layout {
        static let skeletonCount = 12
        static let scrollThreshold: CGFloat = 6
    }

    init(source: Source, preset: SourcePreset) {
        self.source = source
        _vm = State(initialValue: SearchGridViewModel(source: source, preset: preset))
    }

    init(source: Source, query: String) {
        self.source = source
        _vm = State(initialValue: SearchGridViewModel(source: source, query: query))
    }

    init(source: Source) {
        self.source = source
        _vm = State(initialValue: SearchGridViewModel(source: source))
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: dimensions.spacing.space12),
            count: max(1, gridColumns)
        )
    }

    var body: some View {
        @Bindable var vm = vm

        ScrollView(.vertical, showsIndicators: false) {
            Content
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.top, barHeight + dimensions.spacing.space8)
                .padding(.bottom, dimensions.screenMargin)
        }
        .overlay(alignment: .top) {
            VStack(spacing: dimensions.spacing.space12) {
                Searchbar(searchText: $vm.searchText, placeholder: "Search \(vm.sourceName)")
                Header
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space8)
            .padding(.bottom, dimensions.spacing.space12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
            .offset(y: barHidden ? -(barHeight + safeTop) : 0)
            .opacity(barHidden ? 0 : 1)
            .allowsHitTesting(!barHidden)
            .animation(.smooth(duration: 0.25), value: barHidden)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { safeTop = proxy.safeAreaInsets.top }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
            if new <= barHeight {
                barHidden = false
            } else if abs(new - old) > Layout.scrollThreshold {
                barHidden = new > old
            }
        }
        .navigationTitle(vm.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.startObserving() }
        .onDisappear { vm.stopObserving() }
        .navigationDestination(item: $seriesRoute) { stub in
            DetailsScreen(entry: .source(sourceSlug: source.descriptor.slug, stub: stub))
        }
        .sheet(isPresented: $showingRefine) {
            SearchRefineSheet(vm: vm)
        }
    }

    private var Header: some View {
        HStack {
            SortMenu
            Spacer()
            if vm.supportsRefine { RefinePill }
        }
    }

    private var SortMenu: some View {
        Menu {
            ForEach(vm.sortOptions) { option in
                Button {
                    vm.selectSort(option.id)
                } label: {
                    if vm.selectedSortID == option.id {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            Label(vm.selectedSortName, systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.medium))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    @ViewBuilder
    private var RefinePill: some View {
        let count = vm.activeFilterCount
        let active = count > 0

        let button = Button {
            showingRefine = true
        } label: {
            Label(active ? "Refine (\(count))" : "Refine", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(active ? .semibold : .medium))
        }
        .buttonBorderShape(.capsule)

        if active {
            button.buttonStyle(.glassProminent).tint(.brand)
        } else {
            button.buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var Content: some View {
        Group {
            if vm.isLoading, vm.entries.isEmpty {
                Skeleton
            } else if let error = vm.errorMessage, vm.entries.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { vm.retry() }
                }
                .padding(.top, dimensions.spacing.space48)
            } else if vm.entries.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Nothing matched your search.")
                )
                .padding(.top, dimensions.spacing.space48)
            } else {
                Grid
            }
        }
        .transition(.opacity)
        .animation(.smooth(duration: 0.35), value: vm.isLoading)
    }

    private var Grid: some View {
        VStack(spacing: dimensions.spacing.space16) {
            ForEach(pages, id: \.self) { page in
                Section(page)
            }

            if vm.isLoadingMore {
                ProgressView()
                    .padding(.vertical, dimensions.spacing.space16)
            }
        }
    }

    private func Section(_ page: Int) -> some View {
        VStack(spacing: dimensions.spacing.space12) {
            if page > 1 { PageDivider(page) }

            LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
                ForEach(items(for: page)) { entry in
                    SourceCard(stub: entry.stub, referer: vm.referer, match: vm.match(for: entry.stub))
                        .tappable { seriesRoute = entry.stub }
                        .onAppear {
                            if entry.id == vm.entries.last?.id { vm.loadMore() }
                        }
                }
            }
        }
    }

    private func PageDivider(_ page: Int) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Rectangle().fill(.border).frame(height: 1)
            Text("\(page)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.muted)
            Rectangle().fill(.border).frame(height: 1)
        }
    }

    private var Skeleton: some View {
        LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
            ForEach(0..<Layout.skeletonCount, id: \.self) { _ in
                SourceCard()
            }
        }
        .shimmer()
    }

    private var pages: [Int] {
        var seen = Set<Int>()
        return vm.entries.compactMap { seen.insert($0.page).inserted ? $0.page : nil }
    }

    private func items(for page: Int) -> [GridEntry] {
        vm.entries.filter { $0.page == page }
    }
}

//
//  SearchScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct SearchScreen: View {
    var reset: Int = 0
    var source: Source? = nil
    var query: String = ""
    var preset: SourcePreset? = nil
    // only the tab root takes a cross-tab request - a pushed screen cannot be
    // the thing a tab switch lands on
    var seed: Router.Search? = nil
    var embedded: Bool = false

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vm = SearchViewModel()
    @AppStorage(Preferences.Key.bypassAdultSources) private var bypassAdult = Preferences.Default
        .bypassAdultSources
    @State private var seriesRoute: SeriesRoute?
    @State private var gridRoute: GridRoute?
    @State private var gvm: SearchGridViewModel?
    @State private var observing = false
    @State private var showingRefine = false
    @State private var showingSourceSettings = false
    // snapshotted rather than observed - the store is written while a search
    // is running, and the list is only on screen when one is not
    @State private var recents: [String] = []

    private enum Layout {
        static let skeletonCount = 6
        static let carouselVisible = 3
        static let unavailableHeight: CGFloat = 160
        static let heroIcon: CGFloat = 80
        static let heroLift: CGFloat = 24
    }

    private struct SeriesRoute: Identifiable, Hashable {
        let sourceSlug: String
        let stub: SeriesStub

        var id: String { "\(sourceSlug)/\(stub.slug)" }
    }

    private struct GridRoute: Identifiable, Hashable {
        let sourceSlug: String
        let query: String

        var id: String { sourceSlug }
    }

    var body: some View {
        if let source {
            Focused(source)
        } else {
            Global
        }
    }

    @ViewBuilder
    private var Global: some View {
        if embedded {
            GlobalContent
                .navigationTitle(query)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(GlobalLifecycle(vm: vm, seed: query, compositor: compositor))
        } else {
            NavigationStack {
                GlobalContent
                    .toolbarVisibility(vm.active ? .visible : .hidden, for: .navigationBar)
                    .toolbarTitleDisplayMode(.large)
            }
            .modifier(
                GlobalLifecycle(
                    vm: vm, seed: query, compositor: compositor,
                    request: seed
                ) {
                    // a cross-tab request could land on a tab with a series or grid
                    // pushed, seeding a screen nobody can see - pop first
                    seriesRoute = nil
                    gridRoute = nil
                }
            )
            .onChange(of: reset) {
                // two-stage, matching the system tab re-tap convention: pop any
                // pushed screen first, only clear the search on a re-tap at root
                if seriesRoute != nil || gridRoute != nil {
                    seriesRoute = nil
                    gridRoute = nil
                } else {
                    vm.query = ""
                }
            }
        }
    }

    private var GlobalContent: some View {
        @Bindable var vm = vm

        // the field stays in the header for both states rather than being
        // swapped between layouts - a structural swap exactly when `active`
        // flips would tear down the TextField and drop the keyboard mid-word
        return CollapsingHeader {
            VStack(spacing: dimensions.spacing.space12) {
                if !vm.active {
                    Hero
                        .padding(.top, Layout.heroLift)
                        .transition(.replace(reduceMotion: reduceMotion).combined(with: .opacity))
                }

                Searchbar(
                    searchText: $vm.query,
                    placeholder: "Search every source"
                )

                AdultControls
            }
            .animation(.smooth(duration: 0.4), value: vm.active)
        } content: {
            Group {
                if vm.active, vm.allEmpty {
                    ContentUnavailableView.search(text: vm.submitted)
                        .padding(.top, dimensions.spacing.space48)
                        .transition(.replace(reduceMotion: reduceMotion))
                } else if !vm.active {
                    Recents
                        .padding(.horizontal, dimensions.screenMargin)
                        .transition(.replace(reduceMotion: reduceMotion))
                } else {
                    Sections
                        .padding(.horizontal, dimensions.screenMargin)
                        .transition(.replace(reduceMotion: reduceMotion))
                }
            }
            .padding(.bottom, dimensions.screenMargin)
            .animation(.settle, value: vm.stateKey)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "gearshape")
                    .tappable { showingSourceSettings = true }
            }
        }
        .task(id: vm.active) { recents = RecentSearches.entries }
        .task(id: bypassAdult) { vm.bypassAdult = bypassAdult }
        .navigationDestination(item: $seriesRoute) { route in
            DetailsScreen(entry: .source(sourceSlug: route.sourceSlug, stub: route.stub))
        }
        .navigationDestination(item: $gridRoute) { route in
            if let source = compositor.registry.source(slug: route.sourceSlug) {
                SearchScreen(source: source, query: route.query)
            }
        }
        .navigationDestination(isPresented: $showingSourceSettings) { SourceSettingsListScreen() }
    }

    private struct GlobalLifecycle: ViewModifier {
        let vm: SearchViewModel
        let seed: String
        let compositor: Compositor
        var request: Router.Search? = nil
        var onRequest: () -> Void = {}

        func body(content: Content) -> some View {
            content
                .task {
                    // must run after configure, or the search runs against no sources
                    vm.configure(
                        sources: compositor.registry.sources, database: compositor.database)
                    guard !seed.isEmpty, vm.query.isEmpty, vm.submitted.isEmpty else { return }
                    vm.query = seed
                }
                // keyed on the token so asking a second time re-triggers - the
                // unconditional seed above only fires once vm.query is empty.
                // .task rather than .onChange because this view may not have
                // existed yet when the request was made, so there was nothing to
                // observe the change
                .task(id: request?.token) {
                    guard let request else { return }
                    vm.configure(
                        sources: compositor.registry.sources, database: compositor.database)
                    onRequest()
                    vm.query = request.text
                    AppLog.shared.log(
                        "seeded '\(request.text)' token \(request.token)",
                        category: "router")
                }
                .onAppear { vm.resume() }
                .onDisappear { vm.stop() }

        }
    }

    // MARK: Adult sources

    @ViewBuilder
    private var AdultControls: some View {
        if vm.active, vm.hiddenAdultCount > 0 {
            HStack(spacing: dimensions.spacing.space8) {
                Spacer()

                Text("^[\(vm.hiddenAdultCount) source](inflect: true) hidden")
                    .font(.caption)
                    .foregroundStyle(.muted)
            }
            .animation(.smooth(duration: 0.25), value: vm.hiddenAdultCount)
        }
    }

    private func Focused(_ source: Source) -> some View {
        Group {
            if let gvm {
                FocusedContent(source: source, gvm: gvm)
            } else {
                Color.canvas
            }
        }
        .task {
            guard gvm == nil else { return }
            if let preset {
                gvm = SearchGridViewModel(
                    source: source, preset: preset, database: compositor.database)
            } else {
                gvm = SearchGridViewModel(
                    source: source, query: query, database: compositor.database)
            }
        }
    }

    // one shape, always: this screen used to swap between a settings form and a
    // grid depending on whether anything had been typed, which let filters be
    // configured and never run. see features/source-search.md
    @ViewBuilder
    private func FocusedContent(source: Source, gvm: SearchGridViewModel) -> some View {
        @Bindable var gvm = gvm

        CollapsingHeader {
            VStack(spacing: dimensions.spacing.space12) {
                if gvm.supportsSearch {
                    Searchbar(
                        searchText: $gvm.searchText,
                        placeholder: "Search \(source.descriptor.name)"
                    )
                }

                SearchGridControls(vm: gvm) { showingRefine = true }
            }
        } content: {
            SearchResultsGrid(vm: gvm) { stub in
                seriesRoute = SeriesRoute(sourceSlug: source.descriptor.slug, stub: stub)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.screenMargin)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(.canvas)
        .navigationTitle(preset?.name ?? source.descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $seriesRoute) { route in
            DetailsScreen(entry: .source(sourceSlug: route.sourceSlug, stub: route.stub))
        }
        .sheet(isPresented: $showingRefine) {
            SearchRefineSheet(vm: gvm)
        }
        // observation used to stop and reset the moment the field emptied,
        // which made the filters unrunnable - every source accepts a nil query
        // and returns its default listing for one
        .onAppear {
            guard !observing else { return }
            observing = true
            gvm.startObserving()
        }
        .onDisappear {
            gvm.stopObserving()
            observing = false
        }
    }

    private var Hero: some View {
        VStack(spacing: dimensions.spacing.space16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: dimensions.size.icon32))
                .foregroundStyle(.brand)
                .frame(width: Layout.heroIcon, height: Layout.heroIcon)
                .glassEffect(.regular, in: .circle)

            VStack(spacing: dimensions.spacing.space4) {
                Text("Search")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Find series and titles across every source.")
                    .font(.footnote)
                    .foregroundStyle(.muted)
            }
        }
        .padding(.bottom, Layout.heroLift)
    }

    // MARK: Recents

    // stacked cards, not a List - this sits inside the screen's own scroll
    // view, and a nested List brings its own scrolling and insets
    @ViewBuilder
    private var Recents: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                SectionHeader(title: "Recent") {
                    Button("Clear") {
                        RecentSearches.clear()
                        recents = []
                    }
                    .font(.subheadline)
                    .foregroundStyle(.muted)
                }

                VStack(spacing: dimensions.spacing.space8) {
                    ForEach(recents, id: \.self) { entry in
                        RecentRow(entry)
                    }
                }
            }
            .padding(.top, dimensions.spacing.space8)
            .animation(.settle, value: recents)
        }
    }

    private func RecentRow(_ entry: String) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.subheadline)
                .foregroundStyle(.muted)

            Text(entry)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.muted)
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
        .tappable { vm.query = entry }
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) {
                RecentSearches.remove(entry)
                recents = RecentSearches.entries
            }
        }
    }

    private var Sections: some View {
        VStack(spacing: dimensions.spacing.space16) {
            ForEach(vm.sections) { section in
                ResultSection(section)
            }
        }
        .padding(.top, dimensions.spacing.space8)
    }

    private func ResultSection(_ section: SearchViewModel.Section) -> some View {
        SectionCard {
            SectionHead(section)

            switch section.phase {
            case .searching:
                SkeletonCarousel
            case .failed:
                Unavailable {
                    ContentUnavailableView {
                        Label("Couldn't Search", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("Retry") { vm.retry(section.id) }
                    }
                }
            case .loaded where section.stubs.isEmpty:
                Unavailable {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("Nothing from \(section.name) matched.")
                    }
                }
            case .loaded:
                Carousel(section)
            }
        }
    }

    private func SectionHead(_ section: SearchViewModel.Section) -> some View {
        let expandable = section.phase == .loaded && !section.stubs.isEmpty

        return HStack(spacing: dimensions.spacing.space12) {
            Image(section.source.descriptor.icon)
                .resizable()
                .scaledToFit()
                .frame(width: dimensions.size.icon32, height: dimensions.size.icon32)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(section.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Subtitle(section)
                    .font(.footnote)
                    .foregroundStyle(.muted)
            }

            Spacer()

            if expandable {
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.muted)
            }
        }
        .contentShape(.rect)
        .tappable {
            guard expandable else { return }
            gridRoute = GridRoute(sourceSlug: section.id, query: vm.submitted)
        }
    }

    @ViewBuilder
    private func Subtitle(_ section: SearchViewModel.Section) -> some View {
        switch section.phase {
        case .searching:
            Text("Searching")
        case .failed:
            Text("Couldn't search")
        case .loaded:
            if section.hasMore {
                Text("\(SearchViewModel.limit)+ results")
            } else {
                Text("^[\(section.stubs.count) result](inflect: true)")
            }
        }
    }

    private func Carousel(_ section: SearchViewModel.Section) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: dimensions.spacing.space12) {
                ForEach(section.stubs, id: \.slug) { stub in
                    SourceCard(
                        stub: stub,
                        referer: section.source.descriptor.referer,
                        match: vm.match(in: section.id, for: stub)
                    )
                    .containerRelativeFrame(
                        .horizontal,
                        count: Layout.carouselVisible,
                        spacing: dimensions.spacing.space12
                    )
                    .tappable {
                        seriesRoute = SeriesRoute(sourceSlug: section.id, stub: stub)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }

    private var SkeletonCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: dimensions.spacing.space12) {
                ForEach(0..<Layout.skeletonCount, id: \.self) { _ in
                    SourceCard()
                        .containerRelativeFrame(
                            .horizontal,
                            count: Layout.carouselVisible,
                            spacing: dimensions.spacing.space12
                        )
                }
            }
        }
        .scrollDisabled(true)
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func Unavailable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: Layout.unavailableHeight)
    }

    private func SectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            content()
        }
        .padding(dimensions.spacing.space16)
        .background(.surface)
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
    }
}

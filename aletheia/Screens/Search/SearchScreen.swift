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
    // a preset is a standing request - filters and a sort with no text - so the
    // screen opens already searching rather than waiting for input
    var preset: SourcePreset? = nil
    // a pushed screen sits in the presenting tab's stack; only the tab root owns
    // one. a seeded global search is always pushed, so it never owns one either
    var embedded: Bool = false

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vm = SearchViewModel()
    @AppStorage(Preferences.Key.includeAdultSources) private var includeAdult = Preferences.Default.includeAdultSources
    @AppStorage(Preferences.Key.bypassAdultSources) private var bypassAdult = Preferences.Default.bypassAdultSources
    @AppStorage(Preferences.Key.blurAdultSearch) private var blurAdult = Preferences.Default.blurAdultSearch
    @State private var seriesRoute: SeriesRoute?
    @State private var gridRoute: GridRoute?
    @State private var gvm: SearchGridViewModel?
    @State private var observing = false
    @State private var showingRefine = false

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

    // the pushed variants live inside the presenting tab's navigation stack;
    // only the tab-root global variant owns one
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
                    // stated rather than inherited, so all five tab roots declare
                    // the same thing. this root carries no title of its own - the
                    // bar exists only to hold the search field once it is active
                    .toolbarTitleDisplayMode(.large)
            }
            .modifier(GlobalLifecycle(vm: vm, seed: query, compositor: compositor))
            .onChange(of: reset) {
                // two-stage, matching the system convention: a re-tap pops any
                // pushed screen first; only a re-tap already at root clears the
                // search. embedded has no tab to re-tap and no routes of its own
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

        // the field lives in the header for both states rather than being swapped
        // between two layouts - a structural swap on the first keystroke, which
        // is exactly when `active` flips, would tear down the TextField and drop
        // the keyboard mid-word. the hero sits above it in the same stack, so
        // when it collapses only the field's siblings change, never its identity
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
            // both adult decisions in one place: what is fetched, then what is
            // shown. the reveal used to sit in a content row below the field,
            // where it was one of two controls governing the same subject from
            // different halves of the screen
            ToolbarItem(placement: .topBarTrailing) {
                if vm.active {
                    // present but inert when there is nothing to reveal, rather
                    // than absent: a lone slashed eye beside an empty slot reads
                    // as one unexplained control, where the pair reads as a
                    // sentence - these sources are out, so nothing to uncover
                    // writes the stored preference, not a per-search reveal: a
                    // decision you made about covers is one you made once
                    BlurToggle(
                        isOn: !obscured,
                        label: "Adult content",
                        action: { blurAdult = blurAdult.toggled(adultSource: false) }
                    )
                    .disabled(!hasAdultResults)
                }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                // absent entirely without the bypass: while adult sources do not
                // exist, a toggle for them would be the hint that they do
                if vm.active, bypassAdult {
                    // retrieval: whether an adultOnly source is queried at all.
                    // the two states are different things rather than one thing
                    // struck through - a flame when they are in, a covered eye
                    // when they are not
                    AdultToggle(
                        isOn: includeAdult,
                        on: "flame",
                        off: "eye.slash.fill",
                        label: "Adult sources",
                        action: { includeAdult.toggle() }
                    )
                }
            }
        }
        // @AppStorage owns the stored value; the view model mirrors it, so which
        // sources are queried and when the search re-runs stay one decision
        .task(id: includeAdult) { vm.includeAdult = includeAdult }
        .task(id: bypassAdult) { vm.bypassAdult = bypassAdult }
        .navigationDestination(item: $seriesRoute) { route in
            DetailsScreen(entry: .source(sourceSlug: route.sourceSlug, stub: route.stub))
        }
        .navigationDestination(item: $gridRoute) { route in
            if let source = compositor.registry.source(slug: route.sourceSlug) {
                SearchScreen(source: source, query: route.query)
            }
        }
    }

    // shared by both global shapes so the seeding, the correlator lifecycle and
    // the tab re-tap behave identically whether the screen owns its stack or was
    // pushed into someone else's
    private struct GlobalLifecycle: ViewModifier {
        let vm: SearchViewModel
        let seed: String
        let compositor: Compositor

        func body(content: Content) -> some View {
            content
                .task {
                    vm.configure(sources: compositor.registry.sources, database: compositor.database)
                    // after configure, or the search runs against no sources.
                    // only ever seeds the first time - retyping is the reader's
                    guard !seed.isEmpty, vm.query.isEmpty, vm.submitted.isEmpty else { return }
                    vm.query = seed
                }
                .onAppear { vm.resume() }
                .onDisappear { vm.stop() }

        }
    }

    // MARK: Adult sources

    // global search spans every source, so there is no single answer to "did you
    // ask for this" - unset covers
    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    // the toggle is inert until something on screen could be covered by it - a
    // control that changes nothing visible is a control with nothing to say.
    // keyed on the results, not on the preference, so flipping it does not make
    // the button that flipped it disappear
    private var hasAdultResults: Bool {
        vm.sections.contains { section in
            section.stubs.contains { $0.adult }
        }
    }

    // both toggles live in the navbar now, so this row carries only the thing
    // that is a statement rather than a control, and only while it has one
    @ViewBuilder
    private var AdultControls: some View {
        if vm.active, vm.hiddenAdultCount > 0 {
            HStack(spacing: dimensions.spacing.space8) {
                Spacer()

                // an excluded source is otherwise just absent, with nothing
                // saying so - which reads as the search being broken
                Text("^[\(vm.hiddenAdultCount) source](inflect: true) hidden")
                    .font(.caption)
                    .foregroundStyle(.muted)
            }
            .animation(.smooth(duration: 0.25), value: vm.hiddenAdultCount)
        }
    }

    // two different questions, so two different glyphs: a flame is whether adult
    // sources are searched at all, an eye is whether what came back is covered.
    // one symbol for both made "on" ambiguous - on meaning queried, or on meaning
    // visible. filled when active, so the state has a weight channel too
    private struct AdultToggle: View {
        let isOn: Bool
        let on: String
        let off: String
        let label: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: isOn ? on : off)
                    // danger when live, muted when not. green would read as
                    // "correct", which is not a judgement this control makes
                    .foregroundStyle(isOn ? AnyShapeStyle(.danger) : AnyShapeStyle(.muted))
            }
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
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
                gvm = SearchGridViewModel(source: source, preset: preset, database: compositor.database)
            } else {
                gvm = SearchGridViewModel(source: source, query: query, database: compositor.database)
            }
        }
    }

    // one shape, always: field, controls, what is applied, results. the screen
    // used to swap between a seven-row settings form and a grid depending on
    // whether anything had been typed, which meant the filters could be
    // configured and then never run, and the results - the reason for the screen
    // - only existed in one of the two states. see features/source-search.md
    @ViewBuilder
    private func FocusedContent(source: Source, gvm: SearchGridViewModel) -> some View {
        @Bindable var gvm = gvm

        CollapsingHeader {
            VStack(spacing: dimensions.spacing.space12) {
                // no tint for an adult source: the title names it and the blur
                // control sits beside it, so colouring the field only says
                // something already said twice
                Searchbar(
                    searchText: $gvm.searchText,
                    placeholder: "Search \(source.descriptor.name)"
                )

                // no applied-filter rail: the refine sheet lists what is on and is
                // one tap away, and the dot on the pill says that something is
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
        // the preset names itself; without one the source does
        .navigationTitle(preset?.name ?? source.descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // shown whenever the query can return adult results, in either
                // state - gating it on "currently blurred" removed the control
                // that unblurs the moment it was used
                if gvm.gateOpen {
                    let adult = source.descriptor.adultOnly

                    BlurToggle(
                        isOn: !blurAdult.blurs(adultSource: adult),
                        label: "Adult content",
                        action: { blurAdult = blurAdult.toggled(adultSource: adult) }
                    )
                }
            }
        }
        .navigationDestination(item: $seriesRoute) { route in
            DetailsScreen(entry: .source(sourceSlug: route.sourceSlug, stub: route.stub))
        }
        .sheet(isPresented: $showingRefine) {
            SearchRefineSheet(vm: gvm)
        }
        // observation runs for the whole life of the screen, empty query or not.
        // it used to stop and reset the moment the field emptied, which is what
        // made the filters unrunnable - every source already accepts a nil query
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

    // no glass of its own: as a toolbar item the navbar draws the surface, and
    // icons drop to icon24 to sit inside the bar's height
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
            Text("Searching…")
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
                        match: vm.match(in: section.id, for: stub),
                        obscured: obscured && stub.adult
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

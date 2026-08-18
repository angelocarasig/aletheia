//
//  SearchResultsGrid.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

struct SearchResultsGrid: View {
    let vm: SearchGridViewModel
    let onOpen: (SeriesStub) -> Void

    @Environment(\.dimensions) private var dimensions
    @AppStorage(Preferences.Key.gridColumns) private var gridColumns = Preferences.Default
        .gridColumns
    @AppStorage(Preferences.Key.blurAdultSearch) private var blurAdult = Preferences.Default
        .blurAdultSearch
    @State private var currentPage = 1

    // resolved once here rather than per card: the preference and the reveal are
    // both grid-wide, and a section that computed its own could disagree with
    // the switch that is meant to control it
    // an adultOnly source was opened on purpose, so unset shows rather than
    // covers - the home screen for one already renders unblurred, and a grid that
    // disagreed with it made the same source look like two different settings
    private var obscured: Bool { blurAdult.blurs(adultSource: vm.isAdultSource) }

    private enum Layout {
        static let skeletonCount = 12
        static let idleIcon: CGFloat = 72
        // a page section spans several screens, so only a sliver of it is ever
        // visible at once - the threshold has to sit well under that fraction
        static let pageVisibility = 0.1
    }

    // nil is idle: nothing asked for yet, which is neither pending nor empty.
    // branch selector and animation key are one value - the old isLoading key
    // left empty -> content and failure swaps as hard cuts
    private var phase: LoadPhase? {
        if vm.isIdle {
            nil
        } else if vm.isLoading, vm.entries.isEmpty {
            .pending
        } else if vm.failure != nil, vm.entries.isEmpty {
            .failed
        } else if vm.entries.isEmpty {
            .empty
        } else {
            .content
        }
    }

    var body: some View {
        Group {
            switch phase {
            // the prompt names both ways in rather than only the obvious one -
            // the filters are a real entry point now, not decoration
            case nil:
                Idle
                    .padding(.top, dimensions.spacing.space48)
            case .pending:
                Skeleton
            case .failed:
                ContentUnavailableView {
                    Label(
                        vm.failure?.title ?? "Couldn't Search",
                        systemImage: "exclamationmark.triangle")
                } description: {
                    Text(vm.failure?.message ?? "")
                } actions: {
                    if vm.failure?.isRetryable == true {
                        Button("Retry") { vm.retry() }
                    }
                }
                .padding(.top, dimensions.spacing.space48)
            case .empty:
                // filters are the likeliest reason nothing came back, and an
                // empty state that cannot undo the thing that emptied it is a
                // dead end. the action only appears when there is one to undo
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text(emptyReason)
                } actions: {
                    if !vm.applied.isEmpty {
                        Button("Clear Filters") { vm.clearFilters() }
                    }
                }
                .padding(.top, dimensions.spacing.space48)
            case .content:
                Grid
            }
        }
        .transition(.opacity)
        .animation(.settle, value: phase)
    }

    // the source's own identity, not a generic magnifier. this is the one moment
    // the screen has nothing to show, so it says where you are and what the two
    // ways in are - the filters being a real entry point rather than a modifier
    // on a query is the part that is not obvious
    private var Idle: some View {
        VStack(spacing: dimensions.spacing.space16) {
            Image(vm.sourceIcon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.idleIcon, height: Layout.idleIcon)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius16))

            VStack(spacing: dimensions.spacing.space8) {
                Text(vm.sourceName)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(vm.sourceDescription)
                    .font(.footnote)
                    .foregroundStyle(.muted)
            }

            Text("Type to search, or refine to browse by genre, tag or year.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, dimensions.spacing.space4)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, dimensions.screenMargin)
        .frame(maxWidth: .infinity)
    }

    private var emptyReason: String {
        let query = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return switch (query.isEmpty, vm.applied.isEmpty) {
        case (true, true): "\(vm.sourceName) returned nothing."
        case (true, false): "No series match these filters."
        case (false, true): "Nothing matched \"\(query)\"."
        case (false, false): "Nothing matched \"\(query)\" with these filters."
        }
    }

    private var Grid: some View {
        // grouped once per evaluation instead of one O(n) filter per section -
        // this body re-runs on every currentPage write during a fling
        let grouped = Dictionary(grouping: vm.entries, by: \.page)
            .sorted { $0.key < $1.key }

        return VStack(spacing: dimensions.spacing.space16) {
            ForEach(grouped, id: \.key) { page, items in
                PageSection(
                    page: page,
                    entries: items,
                    columnCount: gridColumns,
                    obscured: obscured,
                    vm: vm,
                    onOpen: onOpen
                )
                .equatable()
                .onScrollVisibilityChange(threshold: Layout.pageVisibility) { visible in
                    if visible, currentPage != page { currentPage = page }
                }
            }

            // a persistent slot rather than an inserted-and-removed spinner: the
            // tail growing and shrinking under a finger at max offset is exactly
            // the append-jump this grid used to have
            if vm.hasMore {
                ProgressView()
                    .opacity(vm.isLoadingMore ? 1 : 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: dimensions.size.control)
            }

            if grouped.count > 1 {
                PageFooter(count: grouped.count)
            }
        }
    }

    private func PageFooter(count: Int) -> some View {
        Text("Page \(currentPage) of \(count)")
            .font(.caption)
            .foregroundStyle(.muted)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.3), value: currentPage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, dimensions.spacing.space8)
    }

    private var Skeleton: some View {
        LazyVGrid(
            columns: PageSection.columns(gridColumns, spacing: dimensions.spacing.space12),
            spacing: dimensions.spacing.space16
        ) {
            ForEach(0..<Layout.skeletonCount, id: \.self) { _ in
                SourceCard()
            }
        }
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// its own view with an explicit equality so a mid-scroll state write in the
// parent cannot re-diff every card of every loaded page - a section's body only
// re-runs when its page's rows actually change (observation still invalidates
// it directly for badge updates)
private struct PageSection: View, Equatable {
    let page: Int
    let entries: [GridEntry]
    let columnCount: Int
    let obscured: Bool
    let vm: SearchGridViewModel
    let onOpen: (SeriesStub) -> Void

    @Environment(\.dimensions) private var dimensions

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.page == rhs.page && lhs.columnCount == rhs.columnCount
            && lhs.obscured == rhs.obscured && lhs.entries == rhs.entries
    }

    static func columns(_ count: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count))
    }

    var body: some View {
        VStack(spacing: dimensions.spacing.space12) {
            if page > 1 { PageDivider }

            LazyVGrid(
                columns: Self.columns(columnCount, spacing: dimensions.spacing.space12),
                spacing: dimensions.spacing.space16
            ) {
                ForEach(entries) { entry in
                    SourceCard(
                        stub: entry.stub,
                        referer: vm.referer,
                        match: vm.match(for: entry.stub),
                        obscured: obscured && entry.stub.adult
                    )
                    .tappable { onOpen(entry.stub) }
                    .onAppear {
                        if entry.id == vm.entries.last?.id { vm.loadMore() }
                    }
                }
            }
        }
    }

    // deliberately generous: the gap is the signal. a hairline alone reads as a
    // row separator - the dead space around it is what says "new page starts here"
    private var PageDivider: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Rectangle().fill(.border).frame(height: 1)
            Text("\(page)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.muted)
            Rectangle().fill(.border).frame(height: 1)
        }
        .padding(.vertical, dimensions.spacing.space32)
    }
}

struct SearchGridControls: View {
    let vm: SearchGridViewModel
    let onRefine: () -> Void

    private enum Layout {
        static let dot: CGFloat = 10
        static let dotBorder: CGFloat = 2
        static let dotInset: CGFloat = 2
    }

    // a shelf preset has neither control, and the row goes with them rather than
    // leaving a band of empty glass above the grid
    var body: some View {
        if vm.supportsSort || vm.supportsRefine {
            HStack {
                if vm.supportsSort { SortMenu }
                Spacer()
                if vm.supportsRefine { RefinePill }
            }
        }
    }

    private var SortMenu: some View {
        Menu {
            // a first-class row rather than a clear button. once a sort is picked
            // there is otherwise no way back to whatever the source ranks by, and
            // it names what automatic resolves to instead of leaving it a mystery
            Button {
                vm.selectSort(nil)
            } label: {
                if vm.isDefaultSort {
                    Label(vm.defaultSortName, systemImage: "checkmark")
                } else {
                    Text(vm.defaultSortName)
                }
            }

            Divider()

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

    // the count moves to a dot on the corner: the label stops changing width as
    // filters are added, and the sheet behind it already says how many and which
    @ViewBuilder
    private var RefinePill: some View {
        let active = vm.activeFilterCount > 0

        let button = Button {
            onRefine()
        } label: {
            Label("Refine", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(active ? .semibold : .medium))
        }
        .buttonBorderShape(.capsule)

        Group {
            if active {
                button.buttonStyle(.glassProminent).tint(.brand)
            } else {
                button.buttonStyle(.glass)
            }
        }
        // outside the button so the glass does not sample it, and clear of the
        // capsule's corner so it reads as attached rather than clipped
        .overlay(alignment: .topTrailing) {
            if active {
                Circle()
                    .fill(.danger)
                    .frame(width: Layout.dot, height: Layout.dot)
                    .overlay {
                        Circle().strokeBorder(Color.background, lineWidth: Layout.dotBorder)
                    }
                    .offset(x: Layout.dotInset, y: -Layout.dotInset)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.2), value: active)
        .accessibilityLabel(active ? "Refine, filters applied" : "Refine")
    }
}

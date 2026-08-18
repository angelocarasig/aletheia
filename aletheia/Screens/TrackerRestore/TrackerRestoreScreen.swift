//
//  TrackerRestoreScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import SwiftUI

// the Tagger queue: one page of rows at a time, each auto-searching on
// Search All and committing only on its own Save tap. nothing here writes
// to the database directly - every write happens inside
// TrackerRestoreCommitting.commit
struct TrackerRestoreScreen: View {
    let composer: MigrationComposer<TrackerImportEntry>
    // which tracker this whole session pulled from - the composer no longer
    // carries it (a generic composer's source is fixed at construction, not
    // a field it exposes), and TrackerRestoreRowView still needs it to map
    // each row's own remoteStatus to Status for SavedSummary
    let tracker: Tracker
    let onFinish: () -> Void

    @State private var searchingAll = false
    @State private var confirmingClose = false
    // scrolling down hides the pager, scrolling up brings it back - the same
    // "give the row list the room, keep the chrome one gesture away" shape
    // a collapsing toolbar uses, hand-rolled because this pager is not a
    // system toolbar
    @State private var pagerHidden = false

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let scrollThreshold: CGFloat = 8
    }

    var body: some View {
        ScrollView {
            // .id(composer.filter) is what makes a pill switch a whole-content
            // slide rather than SwiftUI trying to diff two unrelated row sets
            // in place - the subtree is genuinely a new one each time. a row
            // leaving the CURRENT pill (Save, Skip) is a different animation:
            // that's the ForEach's own per-row removal, driven by the
            // .settle-wrapped mutation in TrackerRestoreComposer
            LazyVStack(spacing: dimensions.spacing.space12) {
                ForEach(composer.currentPageRows) { row in
                    TrackerRestoreRowView(
                        row: row,
                        tracker: tracker,
                        sourcesBySlug: composer.sourcesBySlug,
                        onSelect: { candidate in composer.select(candidate, for: row.id) },
                        onSave: { Task { await composer.save(row.id) } },
                        onSkip: { composer.skip(row.id) },
                        onSearch: { query in Task { await composer.search(row.id, query: query) } }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .id(composer.filter)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )
            .animation(.settle, value: composer.filter)
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space12)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { old, new in
            let delta = new - old
            guard abs(delta) > Layout.scrollThreshold else { return }
            withAnimation(.settle) {
                if delta > 0, new > 0 {
                    pagerHidden = true
                } else if delta < 0 {
                    pagerHidden = false
                }
            }
        }
        .navigationTitle("Restoring")
        .navigationSubtitle("\(composer.savedCount) of \(composer.rows.count) saved")
        // this queue is the middle of a process, not a place you back out of
        // one step at a time - once you're in it, the back chevron's "return
        // to setup" no longer applies, so Close ends the whole sheet instead
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") { confirmingClose = true }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    searchingAll = true
                    Task {
                        await composer.searchAllOnCurrentPage()
                        searchingAll = false
                    }
                } label: {
                    if searchingAll {
                        ProgressView()
                    } else {
                        Text("Search All")
                    }
                }
                .disabled(searchingAll)
            }
        }
        .safeAreaInset(edge: .top) {
            if !pagerHidden {
                VStack(spacing: dimensions.spacing.space8) {
                    FilterPills

                    if composer.pageCount > 1 {
                        Pager
                    }
                }
                .background(.canvas)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // closing here is not a plain dismiss - it abandons every row that
        // hasn't been saved yet, so it earns the same confirm a destructive
        // action gets rather than the silent Close a form gives up on
        .alert("End Restore Session?", isPresented: $confirmingClose) {
            Button("End Session", role: .destructive, action: onFinish)
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(closeSummary)
        }
    }

    private var closeSummary: String {
        let total = composer.rows.count
        let saved = composer.savedCount
        let skipped = composer.skippedCount

        var summary = "\(saved) of \(total) saved"
        if skipped > 0 {
            summary += ", \(skipped) skipped"
        }
        summary += ". Anything left unsaved won't be added to your library."
        return summary
    }

    // the same flat, unglassed "Page N of M" SearchResultsGrid.PageFooter
    // uses - a caption in .muted with a numeric-text transition, not a
    // capsule of its own. Previous/Next stay plain buttons beside it, since
    // this pager is discrete rather than scroll-tracked
    private var Pager: some View {
        HStack {
            Button("Previous") { composer.page -= 1 }
                .disabled(composer.page == 0)
            Spacer()
            Text("Page \(composer.page + 1) of \(composer.pageCount)")
                .font(.caption)
                .foregroundStyle(.muted)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.3), value: composer.page)
            Spacer()
            Button("Next") { composer.page += 1 }
                .disabled(composer.page >= composer.pageCount - 1)
        }
        .padding(.horizontal, dimensions.screenMargin)
        .frame(minHeight: dimensions.touchTarget)
    }

    // docs/design.md §4: active filter = tinted background + filled variant
    // + count, never colour alone. each pill states its own count so the
    // reader never has to guess what switching would show.
    //
    // horizontally scrollable rather than a fixed HStack - four pills already
    // presses a compact width, and a fifth pill (a future outcome, or just a
    // longer tracker/count string) should compress the tap target rather than
    // widen the scroller. sized to dimensions.touchTarget, same as any other
    // tappable row in this app - a caption-sized capsule was too small to hit
    // reliably in a queue meant to be worked through quickly
    private var FilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: dimensions.spacing.space8) {
                ForEach(MigrationComposer<TrackerImportEntry>.RowFilter.allCases) { filter in
                    FilterPill(filter)
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
        }
        .padding(.top, dimensions.spacing.space8)
    }

    private func FilterPill(_ filter: MigrationComposer<TrackerImportEntry>.RowFilter) -> some View
    {
        let active = composer.filter == filter
        let count = composer.count(for: filter)

        return Text("\(composer.label(for: filter)) (\(count))")
            .font(.subheadline)
            .fontWeight(active ? .semibold : .regular)
            .foregroundStyle(active ? Palette.brandText : .secondary)
            .padding(.horizontal, dimensions.spacing.space16)
            .frame(minHeight: dimensions.touchTarget)
            .background(
                active ? AnyShapeStyle(Palette.brandSubtle) : AnyShapeStyle(.primary.opacity(0.05)),
                in: .capsule
            )
            .contentShape(.capsule)
            .tappable { composer.filter = filter }
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

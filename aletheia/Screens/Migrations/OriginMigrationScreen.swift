//
//  OriginMigrationScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// file-scope rather than nested - a static stored property is not allowed
// inside a type nested in a generic type
private enum OriginMigrationScreenLayout {
    static let scrollThreshold: CGFloat = 8
}

struct OriginMigrationScreen<Entry: MigrationEntry>: View {
    let composer: MigrationComposer<Entry>
    var savedLabel: String = "Moved"
    let onFinish: () -> Void

    @State private var searchingAll = false
    @State private var confirmingClose = false
    @State private var pagerHidden = false

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        ScrollView {
            LazyVStack(spacing: dimensions.spacing.space12) {
                ForEach(composer.currentPageRows) { row in
                    MigrationRowView(
                        row: row,
                        sourcesBySlug: composer.sourcesBySlug,
                        savedLabel: savedLabel,
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
            guard abs(delta) > OriginMigrationScreenLayout.scrollThreshold else { return }
            withAnimation(.settle) {
                if delta > 0, new > 0 {
                    pagerHidden = true
                } else if delta < 0 {
                    pagerHidden = false
                }
            }
        }
        .navigationTitle("Migrating")
        .navigationSubtitle("\(composer.savedCount) of \(composer.rows.count) saved")
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
        .alert("End Migration?", isPresented: $confirmingClose) {
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
        summary += ". Anything left unsaved won't be migrated."
        return summary
    }

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

    private var FilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: dimensions.spacing.space8) {
                ForEach(MigrationComposer<Entry>.RowFilter.allCases) { filter in
                    FilterPill(filter)
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
        }
        .padding(.top, dimensions.spacing.space8)
    }

    private func FilterPill(_ filter: MigrationComposer<Entry>.RowFilter) -> some View {
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

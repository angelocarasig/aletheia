//
//  DetailsCollections.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsCollections: View {
    let collections: [Item]
    // whether any collection exists at all, which decides what an empty section
    // is telling you: nothing to join, or joined nothing
    let hasAny: Bool
    var onToggle: (Int64) -> Void
    var onPick: () -> Void
    var onCreate: () -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let emptyStateHeight: CGFloat = 180
        static let fillOpacity: Double = 0.05
        static let settle: Animation = .smooth(duration: 0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            SectionHeader("Collections")

            if collections.isEmpty {
                EmptyState
                    .transition(.opacity)
            } else {
                Chips
                    .transition(.opacity)
            }
        }
        // membership is written elsewhere and arrives through the observation, so
        // the tap's own transaction is closed by the time a chip appears
        .animation(Layout.settle, value: collections)
    }

    private var Chips: some View {
        FlowLayout(spacing: dimensions.spacing.space8) {
            ForEach(collections) { collection in
                Chip(collection)
                    .transition(.scale.combined(with: .opacity))
            }

            AddChip
        }
    }

    // only joined collections render here, so presence is the membership
    // signal - no glyph, no tint (redundant confirmation otherwise)
    private func Chip(_ collection: Item) -> some View {
        HStack(spacing: dimensions.spacing.space4) {
            Text(collection.name)
                .font(.subheadline)
                .fontWeight(.medium)

            Text("\(collection.count)")
                .font(.caption)
                .foregroundStyle(.muted)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, dimensions.spacing.space12)
        .padding(.vertical, dimensions.spacing.space8)
        .background(.primary.opacity(Layout.fillOpacity), in: .capsule)
        .contentShape(.capsule)
        .tappable(action: onPick)
        .contextMenu {
            Button("Remove from \(collection.name)", systemImage: "minus.circle") {
                onToggle(collection.id)
            }
        }
    }

    // chips imply collections exist, so this always opens the picker
    private var AddChip: some View {
        HStack(spacing: dimensions.spacing.space4) {
            Image(systemName: "plus")
                .font(.caption)
                .fontWeight(.semibold)

            Text("Add")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundStyle(Palette.brandText)
        .padding(.horizontal, dimensions.spacing.space12)
        .padding(.vertical, dimensions.spacing.space8)
        .background(Palette.brandSubtle, in: .capsule)
        .contentShape(.capsule)
        .tappable(action: onPick)
    }

    private var EmptyState: some View {
        ContentUnavailableView {
            Label("No Collections", systemImage: "rectangle.stack")
        } description: {
            Text(hasAny
                 ? "Add this series to one of your collections"
                 : "Create a collection to organise your library")
        } actions: {
            Button(hasAny ? "Add to Collection" : "Create Collection", action: hasAny ? onPick : onCreate)
                .buttonStyle(.glassProminent)
        }
        .frame(height: Layout.emptyStateHeight)
    }
}

extension DetailsCollections {
    struct Item: Identifiable, Hashable {
        let id: Int64
        let name: String
        let count: Int
        let contains: Bool
    }
}

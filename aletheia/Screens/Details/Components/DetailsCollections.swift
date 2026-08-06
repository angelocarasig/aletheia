//
//  DetailsCollections.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsCollections: View {
    let collections: [Item]

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let cardMinWidth: CGFloat = 120
        static let emptyStateHeight: CGFloat = 180
        static let containsFillOpacity: Double = 0.25
        static let idleFillOpacity: Double = 0.05
        static let newFillOpacity: Double = 0.1
        static let newSubtitleOpacity: Double = 0.6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            SectionHeader(title: "Collections") { AddButton }

            if collections.isEmpty {
                EmptyState
            } else {
                Cards
            }
        }
    }

    private var AddButton: some View {
        Image(systemName: "plus")
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(.muted)
            .frame(width: dimensions.size.control, height: dimensions.size.control)
            .contentShape(.rect)
            .tappable { fatalError("not implemented") }
    }

    private var Cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: dimensions.spacing.space12) {
                ForEach(collections) { collection in
                    Card(collection)
                }

                NewCard
            }
        }
    }

    private func Card(_ collection: Item) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            Text(collection.name)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("^[\(collection.count) item](inflect: true)")
                .font(.caption2)
                .foregroundStyle(.muted)
                .contentTransition(.numericText())
        }
        .frame(minWidth: Layout.cardMinWidth, alignment: .leading)
        .padding(dimensions.spacing.space12)
        .background(fill(for: collection), in: .rect(cornerRadius: dimensions.radius.radius8))
        .contentShape(.rect)
        .tappable { fatalError("not implemented") }
    }

    private var NewCard: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            HStack(spacing: dimensions.spacing.space4) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)

                Text("New")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.brand)

            Text("Create collection")
                .font(.caption2)
                .foregroundStyle(.brand.opacity(Layout.newSubtitleOpacity))
        }
        .frame(minWidth: Layout.cardMinWidth, alignment: .leading)
        .padding(dimensions.spacing.space12)
        .background(.brand.opacity(Layout.newFillOpacity), in: .rect(cornerRadius: dimensions.radius.radius8))
        .contentShape(.rect)
        .tappable { fatalError("not implemented") }
    }

    private var EmptyState: some View {
        ContentUnavailableView {
            Label("No Collections", systemImage: "rectangle.stack")
        } description: {
            Text("Create a collection to organise your library")
        } actions: {
            Button("Create Collection") { fatalError("not implemented") }
                .buttonStyle(.borderedProminent)
        }
        .frame(height: Layout.emptyStateHeight)
    }

    // explicit Color so .brand / .primary resolve unambiguously across the ternary
    private func fill(for collection: Item) -> Color {
        collection.contains
        ? .brand.opacity(Layout.containsFillOpacity)
        : .primary.opacity(Layout.idleFillOpacity)
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

//
//  CollectionPicker.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// membership toggles immediately rather than staging a diff behind a Done
// button - every write comes straight back through the observation, so there is
// no pending state for a cancel to discard
struct CollectionPicker: View {
    let collections: [DetailsCollections.Item]
    let isSaving: Bool
    var onToggle: (Int64) -> Void
    var onCreate: () -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    private enum Layout {
        static let tintOpacity: Double = 0.3
        static let savingOpacity: Double = 0.6
        static let settle: Animation = .smooth(duration: 0.2)
    }

    private var joined: Int {
        collections.count(where: \.contains)
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Collections")
                .navigationSubtitle("^[\(joined) collection](inflect: true) joined")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        // toggles apply instantly, so there is nothing to "do" -
                        // this button only closes
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var Content: some View {
        if collections.isEmpty {
            EmptyState
        } else {
            ScrollView {
                GlassEffectContainer(spacing: dimensions.spacing.space8) {
                    LazyVStack(spacing: dimensions.spacing.space8) {
                        ForEach(collections) { collection in
                            Row(collection)
                                .tappable { onToggle(collection.id) }
                        }

                        Create
                    }
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space24)
            }
            .opacity(isSaving ? Layout.savingOpacity : 1)
            // on an ancestor of every row, so a tick leaving one and landing on
            // another is a single transaction
            .animation(Layout.settle, value: collections)
        }
    }

    private func Row(_ collection: DetailsCollections.Item) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: collection.contains ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(collection.contains ? Palette.brand : Palette.muted)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(collection.name)
                    .font(.subheadline)
                    .fontWeight(collection.contains ? .semibold : .regular)

                Text("^[\(collection.count) series](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.muted)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            collection.contains
                ? .regular.tint(Palette.brand.opacity(Layout.tintOpacity)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
    }

    private var Create: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)

            Text("New Collection")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.brand)
        .padding(dimensions.spacing.space12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: dimensions.radius.radius16))
        .contentShape(.rect)
        .tappable(action: onCreate)
    }

    private var EmptyState: some View {
        ContentUnavailableView {
            Label("No Collections", systemImage: "rectangle.stack")
        } description: {
            Text("Create a collection to organise your library")
        } actions: {
            Button("Create Collection", action: onCreate)
                .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Previews

private enum Sample {
    static let many: [DetailsCollections.Item] = [
        .init(id: 1, name: "Currently Reading", count: 12, contains: true),
        .init(id: 2, name: "Isekai", count: 48, contains: false),
        .init(id: 3, name: "Finished", count: 106, contains: false),
        .init(id: 4, name: "On Hold", count: 3, contains: true),
        .init(id: 5, name: "Recommended by Ren", count: 1, contains: false)
    ]
}

#Preview("Collections") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionPicker(
            collections: Sample.many,
            isSaving: false,
            onToggle: { _ in },
            onCreate: { }
        )
    }
}

#Preview("None joined") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionPicker(
            collections: Sample.many.map { .init(id: $0.id, name: $0.name, count: $0.count, contains: false) },
            isSaving: false,
            onToggle: { _ in },
            onCreate: { }
        )
    }
}

#Preview("Empty") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionPicker(
            collections: [],
            isSaving: false,
            onToggle: { _ in },
            onCreate: { }
        )
    }
}

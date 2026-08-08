//
//  CollectionPicker.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// membership stages locally and commits on Save, matching the chapter
// section's order sheets - Cancel discards the pending diff
struct CollectionPicker: View {
    let collections: [DetailsCollections.Item]
    let isSaving: Bool
    var onToggle: (Int64) -> Void
    var onCreate: () -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var working: Set<Int64>
    @State private var touched = false

    init(
        collections: [DetailsCollections.Item],
        isSaving: Bool,
        onToggle: @escaping (Int64) -> Void,
        onCreate: @escaping () -> Void
    ) {
        self.collections = collections
        self.isSaving = isSaving
        self.onToggle = onToggle
        self.onCreate = onCreate
        _working = State(initialValue: Set(collections.filter(\.contains).map(\.id)))
    }

    private enum Layout {
        static let tintOpacity: Double = 0.3
        static let savingOpacity: Double = 0.6
        static let settle: Animation = .smooth(duration: 0.2)
    }

    // only memberships that actually moved get written
    private var changed: [Int64] {
        collections.filter { working.contains($0.id) != $0.contains }.map(\.id)
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Collections")
                .navigationSubtitle("^[\(working.count) collection](inflect: true) joined")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            changed.forEach(onToggle)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(changed.isEmpty || isSaving)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        // presented before the read lands, so the rows can arrive after init;
        // reseed only while nothing has been staged
        .onChange(of: collections) { _, latest in
            guard !touched else { return }
            working = Set(latest.filter(\.contains).map(\.id))
        }
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
                                .tappable {
                                    touched = true
                                    if working.contains(collection.id) {
                                        working.remove(collection.id)
                                    } else {
                                        working.insert(collection.id)
                                    }
                                }
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
            .animation(Layout.settle, value: working)
        }
    }

    private func Row(_ collection: DetailsCollections.Item) -> some View {
        let contains = working.contains(collection.id)

        return HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: contains ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(contains ? Palette.brand : Palette.muted)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(collection.name)
                    .font(.subheadline)
                    .fontWeight(contains ? .semibold : .regular)

                Text("^[\(collection.count) series](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.muted)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            contains
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

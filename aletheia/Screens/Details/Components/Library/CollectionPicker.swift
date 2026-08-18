//
//  CollectionPicker.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// membership stages locally and commits on Done, matching the chapter
// section's order sheets - Cancel discards the pending diff
struct CollectionPicker: View {
    let collections: [CollectionPicker.Item]
    let isSaving: Bool
    var onToggle: (Int64) -> Void
    var onCreate: (String, String?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var working: Set<Int64>
    @State private var touched = false
    @State private var showingCreate = false

    init(
        collections: [CollectionPicker.Item],
        isSaving: Bool,
        onToggle: @escaping (Int64) -> Void,
        onCreate: @escaping (String, String?) -> Void
    ) {
        self.collections = collections
        self.isSaving = isSaving
        self.onToggle = onToggle
        self.onCreate = onCreate
        _working = State(initialValue: Set(collections.filter(\.contains).map(\.id)))
    }

    private enum Layout {
        static let fillOpacity: Double = 0.05
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
                        Button("Done") {
                            changed.forEach(onToggle)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(changed.isEmpty || isSaving)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingCreate) {
            CollectionForm(isSaving: isSaving, onCreate: onCreate)
        }
        .sensoryFeedback(.selection, trigger: working)
        // presented before the read lands, so the rows can arrive after init;
        // reseed only while nothing has been staged. once staged, still fold in
        // rows created from here (they arrive already joined) or Done would
        // read the new membership as a pending removal
        .onChange(of: collections) { previous, latest in
            if touched {
                let known = Set(previous.map(\.id))
                working.formUnion(latest.filter { !known.contains($0.id) && $0.contains }.map(\.id))
            } else {
                working = Set(latest.filter(\.contains).map(\.id))
            }
        }
    }

    @ViewBuilder
    private var Content: some View {
        if collections.isEmpty {
            EmptyState
        } else {
            ScrollView {
                LazyVStack(spacing: dimensions.spacing.space8) {
                    ForEach(collections) { collection in
                        CollectionRow(collection, joined: working.contains(collection.id))
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
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space24)
            }
            .opacity(isSaving ? Layout.savingOpacity : 1)
            // on an ancestor of every row, so a tick leaving one and landing on
            // another is a single transaction
            .animation(Layout.settle, value: working)
        }
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
        .foregroundStyle(Palette.brandText)
        .padding(dimensions.spacing.space12)
        .background(Palette.brandSubtle, in: .rect(cornerRadius: dimensions.radius.radius12))
        .contentShape(.rect)
        .tappable { showingCreate = true }
    }

    private var EmptyState: some View {
        ContentUnavailableView {
            Label("No Collections", systemImage: "rectangle.stack")
        } description: {
            Text("Create a collection to organise your library")
        } actions: {
            Button("Create Collection") { showingCreate = true }
                .buttonStyle(.glassProminent)
        }
    }
}

extension CollectionPicker {
    // the membership row as the details screen resolves it: every collection
    // that exists, each saying whether this series is in it
    typealias Item = DetailsComposer.Library.Collection
}

// membership is non-exclusive, so the marker is a leading check-circle rather
// than a trailing tick. shared by the staged picker and the instant one in the
// setup flow - the two differ in when they write, never in how a row reads
struct CollectionRow: View {
    let collection: CollectionPicker.Item
    let joined: Bool

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let fillOpacity: Double = 0.05
    }

    init(_ collection: CollectionPicker.Item, joined: Bool) {
        self.collection = collection
        self.joined = joined
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: joined ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(joined ? Palette.brand : Palette.muted)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(collection.name)
                    .font(.subheadline)
                    .fontWeight(joined ? .semibold : .regular)

                Text("^[\(collection.count) series](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.muted)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(dimensions.spacing.space12)
        // flat tinted fill, not glass - rows are content, glass is chrome
        .background(
            joined
                ? AnyShapeStyle(Palette.brandSubtle)
                : AnyShapeStyle(.primary.opacity(Layout.fillOpacity)),
            in: .rect(cornerRadius: dimensions.radius.radius12)
        )
        .contentShape(.rect)
        .accessibilityAddTraits(joined ? .isSelected : [])
    }
}

// MARK: - Previews

private enum Sample {
    static let many: [CollectionPicker.Item] = [
        .init(id: 1, name: "Currently Reading", count: 12, contains: true),
        .init(id: 2, name: "Isekai", count: 48, contains: false),
        .init(id: 3, name: "Finished", count: 106, contains: false),
        .init(id: 4, name: "On Hold", count: 3, contains: true),
        .init(id: 5, name: "Recommended by Ren", count: 1, contains: false),
    ]
}

#Preview("Collections") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionPicker(
            collections: Sample.many,
            isSaving: false,
            onToggle: { _ in },
            onCreate: { _, _ in }
        )
    }
}

#Preview("None joined") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionPicker(
            collections: Sample.many.map {
                .init(id: $0.id, name: $0.name, count: $0.count, contains: false)
            },
            isSaving: false,
            onToggle: { _ in },
            onCreate: { _, _ in }
        )
    }
}

#Preview("Empty") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionPicker(
            collections: [],
            isSaving: false,
            onToggle: { _ in },
            onCreate: { _, _ in }
        )
    }
}

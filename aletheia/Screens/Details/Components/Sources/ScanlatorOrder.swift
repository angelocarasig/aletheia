//
//  ScanlatorOrder.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// sectioned rather than flat - priority is stored per (origin, scanlator), so
// a group ranked first on one site says nothing about its rank on another
struct ScanlatorOrder: View {
    let groups: [Origin]
    let isLoading: Bool
    var onCommit: (Int64, [Int64]) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var working: [Origin]

    private enum Layout {
        static let placeholderOpacity: Double = 0.1
    }

    init(groups: [Origin], isLoading: Bool, onCommit: @escaping (Int64, [Int64]) -> Void) {
        self.groups = groups
        self.isLoading = isLoading
        self.onCommit = onCommit
        _working = State(initialValue: groups)
    }

    private var changed: [Origin] {
        working.filter { group in
            guard let original = groups.first(where: { $0.id == group.id }) else { return false }
            return original.scanlators.map(\.id) != group.scanlators.map(\.id)
        }
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Scanlator Priority")
                .navigationSubtitle("Top group wins a chapter both posted")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            changed.forEach { onCommit($0.id, $0.scanlators.map(\.id)) }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(changed.isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .animation(.settle, value: phase)
        // gated on `working` being empty, not on `changed` being empty - an
        // unloaded list and an untouched one both read as "unchanged", so a
        // guard against `changed` could not tell the two apart
        .onChange(of: groups) { _, latest in
            guard working.isEmpty else { return }
            working = latest
        }
    }
}

// MARK: - Content

extension ScanlatorOrder {
    fileprivate var phase: LoadPhase {
        if !working.isEmpty { .content } else if isLoading { .pending } else { .empty }
    }

    @ViewBuilder
    fileprivate var Content: some View {
        if working.isEmpty, isLoading {
            SheetSkeleton(rows: 6)
                .transition(.opacity)
        } else if working.isEmpty {
            ContentUnavailableView(
                "No Scanlators",
                systemImage: "person.2.slash",
                description: Text("No chapters have been fetched for this series yet.")
            )
            .transition(.opacity)
        } else {
            List {
                ForEach($working) { $group in
                    Section {
                        ForEach(group.scanlators) { scanlator in
                            Row(scanlator)
                        }
                        .onMove { source, destination in
                            group.scanlators.move(fromOffsets: source, toOffset: destination)
                        }
                    } header: {
                        Header(group)
                    }
                }
            }
            // forced active - the drag handles show without a separate Edit button
            .environment(\.editMode, .constant(.active))
            .transition(.opacity)
        }
    }

    fileprivate func Header(_ group: Origin) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Icon(group.icon)

            Text(group.name)
        }
    }

    fileprivate func Row(_ scanlator: Scanlator) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(scanlator.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("^[\(scanlator.chapterCount) chapter](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.muted)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    fileprivate func Icon(_ icon: ImageResource?) -> some View {
        Group {
            if let icon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                    .fill(.primary.opacity(Layout.placeholderOpacity))
            }
        }
        .frame(width: dimensions.size.icon20, height: dimensions.size.icon20)
        .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
    }
}

// MARK: - Model

extension ScanlatorOrder {
    typealias Origin = DetailsComposer.Sources.Group

    typealias Scanlator = DetailsComposer.Sources.Scanlator
}

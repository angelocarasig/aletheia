//
//  ScanlatorOrder.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// the second half of how a merged series decides what you read. origin priority
// picks between sites; this picks between groups posting the same chapter on one
// site, which is what fills a gap the top source never covered.
//
// sectioned rather than flat because priority is stored per (origin, scanlator) -
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

    // only the origins whose order actually moved get written
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
        // presented before the read lands, so the rows arrive after init. gated on
        // being empty rather than unchanged - the same guard written against
        // `changed` never fires, because an empty set differs from a populated one
        .onChange(of: groups) { _, latest in
            guard working.isEmpty else { return }
            working = latest
        }
    }
}

// MARK: - Content

private extension ScanlatorOrder {
    @ViewBuilder
    var Content: some View {
        if working.isEmpty, isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if working.isEmpty {
            ContentUnavailableView(
                "No Scanlators",
                systemImage: "person.2.slash",
                description: Text("No chapters have been fetched for this series yet.")
            )
        } else {
            List {
                ForEach($working) { $group in
                    Section {
                        ForEach(group.scanlators) { scanlator in
                            Row(scanlator)
                        }
                        // scoped to this section: moving a group between origins
                        // would be meaningless, since it is a different ranking
                        .onMove { source, destination in
                            group.scanlators.move(fromOffsets: source, toOffset: destination)
                        }
                    } header: {
                        Header(group)
                    }
                }
            }
            // always active, so the handles are there without an Edit button
            .environment(\.editMode, .constant(.active))
        }
    }

    func Header(_ group: Origin) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Icon(group.icon)

            Text(group.name)
        }
    }

    func Row(_ scanlator: Scanlator) -> some View {
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
    func Icon(_ icon: ImageResource?) -> some View {
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
    struct Origin: Identifiable, Hashable {
        let id: Int64
        let name: String
        let icon: ImageResource?
        var scanlators: [Scanlator]
    }

    struct Scanlator: Identifiable, Hashable {
        let id: Int64
        let name: String
        let chapterCount: Int
    }
}

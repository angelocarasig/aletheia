//
//  OriginOrder.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// presented from both the Sources section and the Chapters header, which is
// why it is not private to either
struct OriginOrder: View {
    let origins: [DetailsSources.Origin]
    var onCommit: ([Int64]) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var working: [DetailsSources.Origin]

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let placeholderOpacity: Double = 0.1
    }

    init(origins: [DetailsSources.Origin], onCommit: @escaping ([Int64]) -> Void) {
        self.origins = origins
        self.onCommit = onCommit
        _working = State(initialValue: origins)
    }

    private var changed: Bool {
        working.map(\.id) != origins.map(\.id)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(working) { origin in
                        Row(origin)
                    }
                    .onMove { source, destination in
                        working.move(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            // forced active - the drag handles show without a separate Edit button
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Source Priority")
            .navigationSubtitle("Top source wins a chapter more than one carries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if changed { onCommit(working.map(\.id)) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!changed)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func Row(_ origin: DetailsSources.Origin) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Icon(origin)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(origin.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(origin.host)
                    .font(.caption2)
                    .foregroundStyle(.muted)
            }

            Spacer(minLength: 0)
        }
        .opacity(origin.unavailable ? Layout.placeholderOpacity + 0.4 : 1)
    }

    @ViewBuilder
    private func Icon(_ origin: DetailsSources.Origin) -> some View {
        Group {
            if let icon = origin.icon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: dimensions.radius.radius8)
                    .fill(.primary.opacity(Layout.placeholderOpacity))
            }
        }
        .frame(width: Layout.iconSize, height: Layout.iconSize)
        .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }
}

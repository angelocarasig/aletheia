//
//  DetailsActions.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsActions: View {
    let inLibrary: Bool
    let isSaving: Bool
    let canToggle: Bool
    let canRefresh: Bool
    let canRefreshMetadata: Bool
    let status: Status
    let collectionCount: Int
    var onToggleLibrary: () -> Void
    var onSetStatus: (Status) -> Void
    var onManageCollections: () -> Void
    var onRefreshChapters: () -> Void
    var onRefreshMetadata: () -> Void
    var onEditDetails: () -> Void
    var onMerge: () -> Void
    var onResetSeries: () -> Void = {}

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let contentLines = 1
        static let detachedOpacity: Double = 0.3
    }

    private struct Square: ViewModifier {
        var tint: Color?
        var label: Color?
        var detached = false

        @Environment(\.dimensions) private var dimensions

        func body(content: Content) -> some View {
            content
                .fontWeight(.medium)
                .foregroundStyle(label ?? .primary)
                .lineLimit(Layout.contentLines)
                .frame(width: dimensions.size.controlL, height: dimensions.size.controlL)
                .glassEffect(
                    glass,
                    in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
                )
                .opacity(detached ? Layout.detachedOpacity : 1)
        }

        private var glass: Glass {
            guard let tint else { return .regular.interactive() }
            return .regular.tint(tint).interactive()
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: dimensions.spacing.space8) {
            HStack(spacing: dimensions.spacing.space8) {
                Primary
                StatusAction
                CollectionsAction
                Overflow
            }
        }
        .frame(height: dimensions.size.controlL)
        .animation(.snappy, value: inLibrary)
        .animation(.snappy, value: isSaving)
        .animation(.snappy, value: status)
        .animation(.snappy, value: collectionCount)
    }

    private var Primary: some View {
        Group {
            if isSaving {
                ProgressView()
                    .tint(label(inLibrary))
            } else {
                Label(
                    inLibrary ? "In Library" : "Add to Library",
                    systemImage: inLibrary ? "heart.fill" : "plus"
                )
            }
        }
        .lineLimit(Layout.contentLines)
        .fontWeight(.medium)
        .padding(.horizontal, dimensions.spacing.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(label(inLibrary))
        .glassEffect(
            inLibrary ? .regular.tint(Palette.textPrimary).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .tappable(action: onToggleLibrary)
        .disabled(!canToggle)
    }

    private func fill(_ on: Bool) -> Color? {
        on ? .textPrimary : nil
    }

    private func label(_ on: Bool) -> Color {
        on ? .canvas : .textPrimary
    }

    private var StatusAction: some View {
        Menu {
            Picker("Status", selection: statusBinding) {
                ForEach(Status.allCases, id: \.self) { value in
                    Label(value.label, systemImage: value.icon).tag(value)
                }
            }
        } label: {
            Label(status.label, systemImage: status.icon)
                .labelStyle(.iconOnly)
                // the write lands from a menu with no animation of its own, so
                // the symbol replace needs one here or it has nothing to run in
                .contentTransition(.symbolEffect(.replace))
                .animation(.settle, value: status)
                .modifier(
                    Square(
                        tint: status.surface,
                        label: status.onSurface,
                        detached: !inLibrary
                    )
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Reading status")
        .accessibilityValue(status.label)
        .disabled(!inLibrary || isSaving)
    }

    private var statusBinding: Binding<Status> {
        Binding(get: { status }, set: onSetStatus)
    }

    private var CollectionsAction: some View {
        Image(systemName: collectionCount > 0 ? "rectangle.stack.fill" : "rectangle.stack")
            .contentTransition(.symbolEffect(.replace))
            .animation(.settle, value: collectionCount > 0)
            .modifier(
                Square(
                    tint: fill(collectionCount > 0),
                    label: collectionCount > 0 ? label(true) : nil,
                    detached: !inLibrary
                )
            )
            .tappable(action: onManageCollections)
            .disabled(!inLibrary || isSaving)
            .accessibilityLabel("Collections")
            .accessibilityValue("^[\(collectionCount) collection](inflect: true) joined")
    }

    private var Overflow: some View {
        Menu {
            Button(action: onEditDetails) {
                Label("Edit Details", systemImage: "pencil")
            }

            Button(action: onRefreshMetadata) {
                Label("Refresh Metadata", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!canRefreshMetadata)

            Button(action: onRefreshChapters) {
                Label("Refresh Chapters", systemImage: "arrow.clockwise")
            }
            .disabled(!canRefresh)

            Button(action: onMerge) {
                Label("Merge Into", systemImage: "arrow.triangle.merge")
            }
            .disabled(!inLibrary)

            Divider()

            Button(role: .destructive, action: onResetSeries) {
                Label("Reset Series", systemImage: "arrow.counterclockwise")
            }
            .disabled(!inLibrary)
        } label: {
            Image(systemName: "ellipsis")
                .modifier(Square(tint: fill(true), label: label(true)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
    }

}

private enum Tint {
    static let opacity: Double = 0.25
}

extension Status {
    var label: String {
        switch self {
        // reads as the reader's own words, not a system state - "finished" is
        // kept apart from Publication's own Completed
        case .reading: "Reading"
        case .completed: "Finished"
        case .paused: "Set Aside"
        case .dropped: "Not for Me"
        case .planning: "Want to Read"
        }
    }

    var tint: Color {
        switch self {
        case .reading: .brandText
        case .completed: .successText
        case .paused: .warningText
        case .dropped: .dangerText
        case .planning: .textPrimary
        }
    }

    var tone: Palette.Tone {
        switch self {
        case .reading: .brand
        case .completed: .success
        case .paused: .warning
        case .dropped: .danger
        case .planning: .neutral
        }
    }

    var surface: Color? {
        switch self {
        case .reading: Palette.brand.opacity(Tint.opacity)
        case .completed: Palette.success.opacity(Tint.opacity)
        case .paused: Palette.warning.opacity(Tint.opacity)
        case .dropped: Palette.danger.opacity(Tint.opacity)
        case .planning: nil
        }
    }

    var onSurface: Color? {
        switch self {
        case .reading: Palette.brandText
        case .completed: Palette.successText
        case .paused: Palette.warningText
        case .dropped: Palette.dangerText
        case .planning: nil
        }
    }

    var icon: String {
        switch self {
        case .reading: "book"
        case .completed: "checkmark.circle"
        case .paused: "pause.circle"
        case .dropped: "xmark.circle"
        case .planning: "clock"
        }
    }
}

// MARK: - Previews

private struct ActionsPreview: View {
    var inLibrary = true
    var isSaving = false
    var canToggle = true
    var canRefresh = true
    var canRefreshMetadata = true
    var status: Status = .reading
    var collectionCount = 2
    let caption: String

    @State private var live: Status?
    @State private var joined: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.muted)

            DetailsActions(
                inLibrary: inLibrary,
                isSaving: isSaving,
                canToggle: canToggle,
                canRefresh: canRefresh,
                canRefreshMetadata: canRefreshMetadata,
                status: live ?? status,
                collectionCount: joined ?? collectionCount,
                onToggleLibrary: {},
                onSetStatus: { live = $0 },
                onManageCollections: { joined = (joined ?? collectionCount) > 0 ? 0 : 3 },
                onRefreshChapters: {},
                onRefreshMetadata: {},
                onEditDetails: {},
                onMerge: {}
            )
        }
    }
}

#Preview("States") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ActionsPreview(inLibrary: false, collectionCount: 0, caption: "Not in library")
            ActionsPreview(collectionCount: 0, caption: "In library, no collections")
            ActionsPreview(caption: "In library, 2 collections")
            ActionsPreview(isSaving: true, caption: "Saving")
            ActionsPreview(
                inLibrary: false, canToggle: false, collectionCount: 0, caption: "Can't toggle yet")
            ActionsPreview(canRefresh: false, caption: "No refreshable origin")
        }
        .padding(16)
    }
    .background(.canvas)
}

#Preview("Status") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Status.allCases, id: \.self) { value in
                ActionsPreview(status: value, collectionCount: 1, caption: value.label)
            }
        }
        .padding(16)
    }
    .background(.canvas)
}

#Preview("Dark") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ActionsPreview(inLibrary: false, collectionCount: 0, caption: "Not in library")
            ActionsPreview(caption: "In library, 2 collections")
            ActionsPreview(status: .dropped, collectionCount: 0, caption: "Dropped, no collections")
        }
        .padding(16)
    }
    .background(.canvas)
    .environment(\.colorScheme, .dark)
}

#Preview("Narrow") {
    ActionsPreview(caption: "320pt")
        .padding(16)
        .frame(width: 320)
        .background(.canvas)
}

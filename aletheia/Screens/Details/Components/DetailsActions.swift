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
    let status: Status
    var onToggleLibrary: () -> Void
    var onSetStatus: (Status) -> Void
    var onRefreshChapters: () -> Void
    var onMarkAll: (Bool) -> Void
    var onEditDetails: () -> Void
    var onMerge: () -> Void
    // the bulk half of downloads. per-chapter lives on the chapter row, where
    // the thing being acted on is
    var onDownloadUnread: () -> Void = {}
    var onDeleteDownloads: () -> Void = {}

    @Environment(\.dimensions) private var dimensions
    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let contentLines = 1
        static let detachedOpacity: Double = 0.5
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Primary
            StatusAction
            Overflow
        }
        .frame(height: dimensions.size.controlL)
        .animation(.snappy, value: inLibrary)
        .animation(.snappy, value: isSaving)
        .animation(.snappy, value: status)
    }

    private var Primary: some View {
        Group {
            if isSaving {
                ProgressView()
                    .tint(foreground)
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
        .foregroundStyle(foreground)
        .background(background, in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
        .tappable(action: onToggleLibrary)
        .disabled(!canToggle)
    }

    // where the user is with the series, which only means anything once it is
    // theirs - outside the library every series would claim to be "planning"
    private var StatusAction: some View {
        Menu {
            Picker("Status", selection: statusBinding) {
                ForEach(Status.allCases, id: \.self) { value in
                    Label(value.label, systemImage: value.icon).tag(value)
                }
            }
        } label: {
            Label(status.label, systemImage: status.icon)
                // the write lands from a menu with no animation of its own, so
                // the glyph needs one here or the replace has nothing to run in
                .contentTransition(.symbolEffect(.replace))
                .animation(.settle, value: status)
                .lineLimit(Layout.contentLines)
                .fontWeight(.medium)
                // the fill is the inverse of the current scheme, so the tint has
                // to resolve against that - left alone, dark mode would put a
                // light blue on white. only the label is inverted; padding and
                // background wrap it, so they still see the real scheme
                .foregroundStyle(status.tint)
                .environment(\.colorScheme, inverted)
                .padding(.horizontal, dimensions.spacing.space8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.textPrimary, in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
                .opacity(inLibrary ? 1 : Layout.detachedOpacity)
        }
        // the menu does not inherit the label's fill, so it has to be sized here
        // too or the row ends up shorter than the toggle beside it
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(!inLibrary || isSaving)
    }

    private var statusBinding: Binding<Status> {
        Binding(get: { status }, set: onSetStatus)
    }

    private var Overflow: some View {
        Menu {
            Button(action: onEditDetails) {
                Label("Edit Details", systemImage: "pencil")
            }

            Button(action: onRefreshChapters) {
                Label("Refresh Chapters", systemImage: "arrow.clockwise")
            }
            .disabled(!canRefresh)

            // merging pulls this series into another one you own, so it only
            // means something once both sides can be library rows
            Button(action: onMerge) {
                Label("Merge Into…", systemImage: "arrow.triangle.merge")
            }
            .disabled(!inLibrary)

            Divider()

            Button(action: onDownloadUnread) {
                Label("Download Unread", systemImage: "arrow.down.circle")
            }
            .disabled(!canRefresh)

            Button(role: .destructive, action: onDeleteDownloads) {
                Label("Delete Downloads", systemImage: "trash")
            }

            Divider()

            Button { onMarkAll(true) } label: {
                Label("Mark All as Read", systemImage: "checkmark.circle.fill")
            }

            Button { onMarkAll(false) } label: {
                Label("Mark All as Unread", systemImage: "x.circle.fill")
            }
        } label: {
            Image(systemName: "ellipsis")
                .fontWeight(.medium)
                .frame(width: dimensions.size.controlL, height: dimensions.size.controlL)
                .foregroundStyle(.canvas)
                .background(.textPrimary, in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
        }
    }

    // the active state inverts - filled with the text colour, lettered in the canvas colour
    private var foreground: Color {
        inLibrary ? .canvas : .textPrimary
    }

    private var background: Color {
        inLibrary ? .textPrimary : .surface
    }

    private var inverted: ColorScheme {
        colorScheme == .dark ? .light : .dark
    }
}

extension Status {
    var label: String {
        switch self {
        case .reading: "Reading"
        case .completed: "Completed"
        case .paused: "Paused"
        case .dropped: "Dropped"
        case .planning: "Plan to Read"
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

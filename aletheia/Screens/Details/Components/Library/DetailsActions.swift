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
    // how many collections hold this series. only the zero/non-zero distinction
    // is drawn, but the count is what the menu needs to describe itself
    let collectionCount: Int
    var onToggleLibrary: () -> Void
    var onSetStatus: (Status) -> Void
    var onManageCollections: () -> Void
    var onRefreshChapters: () -> Void
    var onRefreshMetadata: () -> Void
    var onMarkAll: (Bool) -> Void
    var onEditDetails: () -> Void
    var onMerge: () -> Void
    // the bulk half of downloads. per-chapter lives on the chapter row, where
    // the thing being acted on is
    var onDownloadUnread: () -> Void = {}
    var onDeleteDownloads: () -> Void = {}

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let contentLines = 1
        static let detachedOpacity: Double = 0.3
    }

    // the three fixed-width controls share one shape, so the row reads as a
    // primary ask followed by a strip of things already answered. glass rather
    // than a solid slab: at 44pt these are small elements, so each flips light
    // or dark against whatever the header leaves behind them
    private struct Square: ViewModifier {
        var tint: Color?
        // pinned only where the tint is opaque enough that the surface has
        // stopped deciding for itself. left nil, glass vends its own answer,
        // which is the rule everywhere the tint is a semantic wash
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

    // one primary and three squares: the squares are the things you already own
    // the answer to, so they cost a fixed sliver each and the ask takes the rest
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

    // on inverts: the text colour becomes the fill and the canvas colour the
    // lettering. an accent would say "this is the interesting one", and owned is
    // the resting state - inversion says it without spending a hue. the tint is
    // opaque enough to stop glass choosing its own content colour, which is why
    // these two are the only pinned foregrounds here
    private func fill(_ on: Bool) -> Color? {
        on ? .textPrimary : nil
    }

    private func label(_ on: Bool) -> Color {
        on ? .canvas : .textPrimary
    }

    // where the user is with the series, which only means anything once it is
    // theirs - outside the library every series would claim to be "planning".
    //
    // a square like the two beside it rather than the word it used to spell: the
    // primary is the only thing on this row still being asked, and a control
    // stating an answer at twice the width of its neighbours took that place.
    // what carries the meaning instead is glyph plus tint, and the menu names
    // all five the moment it opens - which is the only time the exact word
    // decides anything, since reading it is not what changes it
    private var StatusAction: some View {
        Menu {
            Picker("Status", selection: statusBinding) {
                ForEach(Status.allCases, id: \.self) { value in
                    Label(value.label, systemImage: value.icon).tag(value)
                }
            }
        } label: {
            // iconOnly rather than a bare Image: the word is gone from the screen
            // and not from VoiceOver, which reads the label it still carries
            Label(status.label, systemImage: status.icon)
                .labelStyle(.iconOnly)
                // the write lands from a menu with no animation of its own, so
                // the glyph needs one here or the replace has nothing to run in
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
        // menus tint their own label with the accent colour whatever the content
        // says, which would overrule the glass's own answer
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Reading status")
        .accessibilityValue(status.label)
        .disabled(!inLibrary || isSaving)
    }

    private var statusBinding: Binding<Status> {
        Binding(get: { status }, set: onSetStatus)
    }

    // membership is non-exclusive, so the filled variant is the channel - a count
    // on a 44pt square would be unreadable, and the picker states the number
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

            // merging pulls this series into another one you own, so it only
            // means something once both sides can be library rows
            Button(action: onMerge) {
                Label("Merge Into", systemImage: "arrow.triangle.merge")
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
            // always inverted, never off: overflow has no state to report, so
            // the one fixed anchor in the row is the thing that always looks the
            // same. it is also what the other two invert *to*, which is what
            // makes their on-state read as arriving somewhere
            Image(systemName: "ellipsis")
                .modifier(Square(tint: fill(true), label: label(true)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
    }

}

// the tint marks a state, it does not fill a button - at full strength the
// status square read as loud as the primary beside it, which inverts the row's
// hierarchy. the glyph keeps the *Text step, so the colour channel survives the
// quieter wash
private enum Tint {
    static let opacity: Double = 0.25
}

extension Status {
    var label: String {
        switch self {
        // each one is a sentence the reader said about themselves, so it reads as
        // their words rather than a system state. "set aside" and "not for me"
        // carry the might-come-back distinction that paused and dropped left to
        // be guessed, and "finished" keeps the reader's answer apart from the
        // work's own Completed
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

    // the same five meanings as a Badge tone, which pairs step 11 text on step 3
    // background rather than letting a fill colour be drawn as text. planning is
    // neutral for the reason above: it is where every series starts, so it is not
    // worth an accent
    var tone: Palette.Tone {
        switch self {
        case .reading: .brand
        case .completed: .success
        case .paused: .warning
        case .dropped: .danger
        case .planning: .neutral
        }
    }

    // the surface tint, not the glyph colour - the *Text steps are drawn on a
    // subtle background, and a glass tint is a fill. status is the one control
    // that keeps a hue: five states that genuinely differ, where the other two
    // are on/off and invert instead
    var surface: Color? {
        switch self {
        case .reading: Palette.brand.opacity(Tint.opacity)
        case .completed: Palette.success.opacity(Tint.opacity)
        case .paused: Palette.warning.opacity(Tint.opacity)
        case .dropped: Palette.danger.opacity(Tint.opacity)
        // no tint: the accent is spent on states that vary, and plan-to-read is
        // where every series starts
        case .planning: nil
        }
    }

    // a semantic wash is not opaque, so the glyph stays legible drawn in the
    // same family's text step rather than left to glass. planning has no wash
    // and no pin
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
                onMarkAll: { _ in },
                onEditDetails: {},
                onMerge: {}
            )
        }
    }
}

// every state the row can be in, stacked, so a design change can be judged
// against all of them at once rather than one screenshot at a time
#Preview("States") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ActionsPreview(inLibrary: false, collectionCount: 0, caption: "Not in library")
            ActionsPreview(collectionCount: 0, caption: "In library, no collections")
            ActionsPreview(caption: "In library, 2 collections")
            ActionsPreview(isSaving: true, caption: "Saving")
            ActionsPreview(inLibrary: false, canToggle: false, collectionCount: 0, caption: "Can't toggle yet")
            ActionsPreview(canRefresh: false, caption: "No refreshable origin")
        }
        .padding(16)
    }
    .background(.canvas)
}

// the status square is the only control whose glyph and tint both move, so it
// gets its own sweep - the five sit closest together at this size
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

// the row lives under the header at full width; a narrow container is where the
// primary label truncates first, which is what a redesign has to survive
#Preview("Narrow") {
    ActionsPreview(caption: "320pt")
        .padding(16)
        .frame(width: 320)
        .background(.canvas)
}

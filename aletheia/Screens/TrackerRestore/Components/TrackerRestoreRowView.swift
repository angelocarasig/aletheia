//
//  TrackerRestoreRowView.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Kingfisher
import SwiftUI

struct TrackerRestoreRowView: View {
    let row: MigrationRow<TrackerImportEntry>
    let tracker: Tracker
    let sourcesBySlug: [String: Source]
    let onSelect: (MigrationCandidate) -> Void
    let onSave: () -> Void
    let onSkip: () -> Void
    let onSearch: (String?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPicker = false

    private enum Layout {
        static let sourceIconSize: CGFloat = 20
        static let promptHeight: CGFloat = 64
        static let carouselVisible = 3
        static let previewCount = 8
        static let tint: Double = 0.25
        static let savedCoverWidth: CGFloat = 64
        static let savedCoverAspect: CGFloat = 11 / 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            HStack {
                Text(row.entry.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                StatusIcon

                if case .found = row.match, row.outcome != .saved {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                        .tappable { showingPicker = true }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if row.precheckMatched {
                    AlreadyLinkedPrompt
                        .transition(.opacity)
                } else {
                    switch row.match {
                    case .idle:
                        SearchPrompt
                            .transition(.opacity)

                    case .searching:
                        SearchingPrompt
                            .transition(.opacity)

                    case .found(let candidates, let selected):
                        if row.outcome == .saved {
                            SavedSummary(selected)
                                .transition(.opacity)
                        } else {
                            ResultsCarousel(candidates, selected: selected)
                                .transition(.opacity)
                        }

                    case .notFound:
                        NoMatchPrompt
                            .transition(.opacity)

                    case .failed(let reason):
                        FailurePrompt(reason)
                            .transition(.opacity)
                    }
                }
            }

            if let reason = row.outcome?.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.warningText)
                    .lineLimit(2)
            }

            // row.saving is checked separately from canSave - canSave is false while
            // saving, so folding it in made the row disappear mid-save with no indicator
            if row.saving || row.canSave || row.canSkip {
                HStack {
                    Spacer()
                    if row.saving {
                        SaveButton
                    } else if row.canSkip {
                        SkipButton
                    } else {
                        SaveButton
                    }
                }
            }
        }
        .animation(.settle, value: row.match)
        .animation(.settle, value: row.outcome)
        .animation(.settle, value: row.saving)
        .padding(dimensions.spacing.space12)
        .glassEffect(
            .regular, in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .sheet(isPresented: $showingPicker) {
            MigrationCandidatePicker(
                title: row.entry.title,
                candidates: row.match.candidates,
                selected: row.match.selected,
                sourcesBySlug: sourcesBySlug,
                searching: row.match == .searching,
                onSearch: { onSearch($0) },
                onSelect: onSelect
            )
        }
    }

    private var SaveButton: some View {
        HStack(spacing: dimensions.spacing.space8) {
            if row.saving {
                ProgressView()
            } else {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
            }
            Text(row.saving ? "Saving" : "Save")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(row.canSave ? Palette.brandText : .secondary)
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space8)
        .glassEffect(
            row.canSave
                ? .regular.tint(Palette.brand.opacity(Layout.tint)).interactive()
                : .regular,
            in: .capsule
        )
        .contentShape(.capsule)
        .tappable(action: onSave)
        .disabled(!row.canSave)
    }

    private var SkipButton: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "arrow.uturn.forward")
                .font(.caption.weight(.semibold))
            Text("Skip")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space8)
        .glassEffect(.regular.tint(Palette.muted.opacity(Layout.tint)).interactive(), in: .capsule)
        .contentShape(.capsule)
        .tappable(action: onSkip)
    }

    @ViewBuilder
    private var StatusIcon: some View {
        if row.precheckMatched {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(.secondary)
                .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
        } else if row.saving {
            Image(systemName: "progress.indicator")
                .foregroundStyle(.secondary)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
        } else {
            switch (row.match, row.outcome) {
            case (_, .saved):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.success)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            case (_, .failed):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.warningText)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            case (_, .skipped):
                Image(systemName: "arrow.uturn.forward.circle.fill")
                    .foregroundStyle(.secondary)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            case (.searching, nil):
                Image(systemName: "progress.indicator")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            default:
                EmptyView()
            }
        }
    }

    private var AlreadyLinkedPrompt: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(.secondary)
            Text("Already in your library")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.promptHeight)
    }

    private func SavedSummary(_ selected: MigrationCandidate?) -> some View {
        let status = Status(raw: row.entry.remoteStatus, for: tracker) ?? .planning

        return HStack(spacing: dimensions.spacing.space12) {
            SavedCover(selected?.stub.cover)

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Badge(text: status.label, tone: status.tone, size: .compact)

                VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                    if let total = row.entry.totalChapters, total > 0 {
                        ProgressView(value: Double(row.entry.progress), total: Double(total))
                            .tint(.brand)
                    }

                    ProgressText
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // separate branches, not `??` into a String - coalescing broke inflection
    // markup here before (docs/findings.md)
    @ViewBuilder
    private var ProgressText: some View {
        if let total = row.entry.totalChapters, total > 0 {
            Text("\(row.entry.progress) of \(total)")
        } else {
            Text("^[\(row.entry.progress) chapter](inflect: true) read")
        }
    }

    private func SavedCover(_ url: URL?) -> some View {
        Color.clear
            .aspectRatio(Layout.savedCoverAspect, contentMode: .fit)
            .frame(width: Layout.savedCoverWidth)
            .overlay {
                if let url {
                    KFImage(url)
                        .resizable()
                        .placeholder { Rectangle().fill(.primary.opacity(0.1)) }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(0.1))
                }
            }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
            .clipped()
    }

    private var SearchPrompt: some View {
        VStack(spacing: dimensions.spacing.space4) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(Palette.brand)
            Text("Tap to Search")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.promptHeight)
        .contentShape(.rect)
        .tappable { onSearch(nil) }
    }

    private var SearchingPrompt: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: dimensions.spacing.space8) {
                ForEach(0..<Layout.carouselVisible, id: \.self) { _ in
                    SourceCard()
                        .containerRelativeFrame(
                            .horizontal,
                            count: Layout.carouselVisible,
                            spacing: dimensions.spacing.space8
                        )
                }
            }
        }
        .scrollDisabled(true)
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityLabel("Searching")
    }

    private var NoMatchPrompt: some View {
        ContentUnavailableView {
            Label("No Match Found", systemImage: "magnifyingglass")
        } description: {
            Text("No installed source had a result for this title.")
        } actions: {
            DeadEndActions
        }
    }

    private func FailurePrompt(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            DeadEndActions
        }
    }

    private var DeadEndActions: some View {
        Button("Retry") { onSearch(nil) }
    }

    private func ResultsCarousel(_ candidates: [MigrationCandidate], selected: MigrationCandidate?)
        -> some View
    {
        let shown = candidates.prefix(Layout.previewCount)

        return VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Subheadline(candidates, selected: selected)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: dimensions.spacing.space8) {
                    ForEach(Array(shown)) { candidate in
                        let source = sourcesBySlug[candidate.sourceSlug]

                        SourceCard(
                            stub: candidate.stub, referer: source?.descriptor.referer,
                            selected: candidate == selected
                        )
                        .animation(.settle, value: candidate == selected)
                        .overlay(alignment: .topLeading) { SourceIcon(source) }
                        .containerRelativeFrame(
                            .horizontal,
                            count: Layout.carouselVisible,
                            spacing: dimensions.spacing.space8
                        )
                        .contentShape(.rect)
                        .tappable { onSelect(candidate) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func Subheadline(_ candidates: [MigrationCandidate], selected: MigrationCandidate?)
        -> some View
    {
        if let selected {
            Text(sourcesBySlug[selected.sourceSlug]?.descriptor.name ?? selected.sourceSlug)
        } else {
            Text("^[\(candidates.count) match](inflect: true) found")
        }
    }

    @ViewBuilder
    private func SourceIcon(_ source: Source?) -> some View {
        if let icon = source?.descriptor.icon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.sourceIconSize, height: Layout.sourceIconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
                .padding(dimensions.spacing.space4)
        }
    }
}

#if DEBUG
    private struct RowPreview: View {
        @State private var index = 0

        private static let source = AtsumaruSource(network: NetworkService())
        private static let sourcesBySlug: [String: Source] = [source.descriptor.slug: source]

        private static func entry(_ id: Int64, _ title: String) -> TrackerImportEntry {
            TrackerImportEntry(
                id: id, title: title, cover: nil, progress: 42, remoteStatus: "CURRENT",
                totalChapters: nil)
        }

        private static func candidate(_ slug: String, _ title: String) -> MigrationCandidate {
            MigrationCandidate(
                sourceSlug: source.descriptor.slug,
                stub: SeriesStub(slug: slug, title: title, cover: nil))
        }

        private static let ambiguous = [
            candidate("a", "Solo Leveling: Ragnarok"), candidate("b", "Solo Leveling (Volume)"),
            candidate("c", "Only I Level Up"),
        ]
        private static let exact = [
            candidate("a", "Chainsaw Man"), candidate("b", "Chainsaw Man: Volume 1"),
        ]

        private static let states: [(name: String, row: MigrationRow<TrackerImportEntry>)] = [
            ("Idle", MigrationRow<TrackerImportEntry>(entry: entry(1, "Solo Leveling"))),
            (
                "Already linked",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(11, "Vagabond"), precheckMatched: true)
            ),
            (
                "Searching",
                MigrationRow<TrackerImportEntry>(entry: entry(2, "Chainsaw Man"), match: .searching)
            ),
            (
                "Found, ambiguous",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(3, "Solo Leveling"), match: .found(ambiguous, selected: nil))
            ),
            (
                "Found, exact match auto-selected",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(4, "Chainsaw Man"), match: .found(exact, selected: exact[0]))
            ),
            (
                "Saving",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(5, "Chainsaw Man"), match: .found(exact, selected: exact[0]),
                    saving: true)
            ),
            (
                "Saved",
                MigrationRow<TrackerImportEntry>(
                    entry: TrackerImportEntry(
                        id: 6, title: "Chainsaw Man", cover: nil, progress: 97,
                        remoteStatus: "CURRENT", totalChapters: 156),
                    match: .found(exact, selected: exact[0]),
                    outcome: .saved
                )
            ),
            (
                "Not found",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(7, "A Fabricated Title"), match: .notFound)
            ),
            (
                "Search failed",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(8, "One Piece"), match: .failed("Every source failed to respond."))
            ),
            (
                "Save failed - offers Skip",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(9, "Chainsaw Man"),
                    match: .found(exact, selected: exact[0]),
                    outcome: .failed("You're not signed in to AniList.")
                )
            ),
            (
                "Skipped",
                MigrationRow<TrackerImportEntry>(
                    entry: entry(10, "Chainsaw Man"),
                    match: .found(exact, selected: exact[0]),
                    outcome: .skipped("You're not signed in to AniList.")
                )
            ),
        ]

        private var state: (name: String, row: MigrationRow<TrackerImportEntry>) {
            Self.states[index]
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("Previous") { step(-1) }
                    Button("Next") { step(1) }
                    Spacer()
                    Text("\(index + 1)/\(Self.states.count)")
                        .font(.caption)
                        .foregroundStyle(.muted)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text(state.name)
                    .font(.caption)
                    .foregroundStyle(.muted)

                TrackerRestoreRowView(
                    row: state.row,
                    tracker: .anilist,
                    sourcesBySlug: Self.sourcesBySlug,
                    onSelect: { _ in },
                    onSave: {},
                    onSkip: {},
                    onSearch: { _ in }
                )

                Spacer()
            }
            .padding(16)
            .background(.canvas)
        }

        private func step(_ delta: Int) {
            index = (index + delta + Self.states.count) % Self.states.count
        }
    }

    #Preview("Row states") {
        RowPreview()
    }
#endif

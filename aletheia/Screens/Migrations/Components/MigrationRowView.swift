//
//  MigrationRowView.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI
import Kingfisher

// file-scope rather than nested - a static stored property is not allowed
// inside a type nested in a generic type
private enum MigrationRowLayout {
    static let sourceIconSize: CGFloat = 20
    static let promptHeight: CGFloat = 64
    static let carouselVisible = 3
    static let previewCount = 8
    static let tint: Double = 0.25
    static let savedCoverWidth: CGFloat = 64
    static let savedCoverAspect: CGFloat = 11 / 16
}

// one queue row, generic over the entry type - the same shape
// TrackerRestoreRowView uses (idle/searching/found/notFound/failed/saving/
// saved, one glass card, one Save-or-Skip slot), stripped of everything
// that only meant something for a tracker's own list: no remoteStatus badge,
// no progress bar, no "already linked" precheck state - none of the flows
// that reach this view populate one. shared by source migration,
// disconnected migration, and backup import - tracker restore keeps its
// own bespoke row, since it is the one flow with real per-entry fields
// (progress, totalChapters, remoteStatus) to show
struct MigrationRowView<Entry: MigrationEntry>: View {
    let row: MigrationRow<Entry>
    let sourcesBySlug: [String: Source]
    // "Moved" reads right for a source migration; a different flow names
    // its own saved state (backup import: "Restored")
    var savedLabel: String = "Moved"
    let onSelect: (MigrationCandidate) -> Void
    let onSave: () -> Void
    let onSkip: () -> Void
    let onSearch: (String?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPicker = false

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
                switch row.match {
                case .idle:
                    SearchPrompt
                        .transition(.opacity)

                case .searching:
                    SearchingPrompt
                        .transition(.opacity)

                case let .found(candidates, selected):
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

                case let .failed(reason):
                    FailurePrompt(reason)
                        .transition(.opacity)
                }
            }

            if let reason = row.outcome?.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.warningText)
                    .lineLimit(2)
            }

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
        .glassEffect(.regular, in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
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
                ? .regular.tint(Palette.brand.opacity(MigrationRowLayout.tint)).interactive()
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
        .glassEffect(.regular.tint(Palette.muted.opacity(MigrationRowLayout.tint)).interactive(), in: .capsule)
        .contentShape(.capsule)
        .tappable(action: onSkip)
    }

    @ViewBuilder
    private var StatusIcon: some View {
        if row.saving {
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

    // a mix of both halves of what a saved row knows: the candidate's own
    // cover (what the source showed for it), and which source it landed on
    // - no progress bar here, unlike tracker restore's SavedSummary, since
    // progress was copied from a real local origin rather than a number the
    // reader might want to double check
    private func SavedSummary(_ selected: MigrationCandidate?) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            SavedCover(selected?.stub.cover)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(savedLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.success)

                if let name = selected.flatMap({ sourcesBySlug[$0.sourceSlug]?.descriptor.name }) {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func SavedCover(_ url: URL?) -> some View {
        Color.clear
            .aspectRatio(MigrationRowLayout.savedCoverAspect, contentMode: .fit)
            .frame(width: MigrationRowLayout.savedCoverWidth)
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
        .frame(height: MigrationRowLayout.promptHeight)
        .contentShape(.rect)
        .tappable { onSearch(nil) }
    }

    private var SearchingPrompt: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: dimensions.spacing.space8) {
                ForEach(0..<MigrationRowLayout.carouselVisible, id: \.self) { _ in
                    SourceCard()
                        .containerRelativeFrame(
                            .horizontal,
                            count: MigrationRowLayout.carouselVisible,
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

    private func ResultsCarousel(_ candidates: [MigrationCandidate], selected: MigrationCandidate?) -> some View {
        let shown = candidates.prefix(MigrationRowLayout.previewCount)

        return VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Subheadline(candidates, selected: selected)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: dimensions.spacing.space8) {
                    ForEach(Array(shown)) { candidate in
                        let source = sourcesBySlug[candidate.sourceSlug]

                        SourceCard(stub: candidate.stub, referer: source?.descriptor.referer, selected: candidate == selected)
                            .animation(.settle, value: candidate == selected)
                            .overlay(alignment: .topLeading) { SourceIcon(source) }
                            .containerRelativeFrame(
                                .horizontal,
                                count: MigrationRowLayout.carouselVisible,
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
    private func Subheadline(_ candidates: [MigrationCandidate], selected: MigrationCandidate?) -> some View {
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
                .frame(width: MigrationRowLayout.sourceIconSize, height: MigrationRowLayout.sourceIconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
                .padding(dimensions.spacing.space4)
        }
    }
}

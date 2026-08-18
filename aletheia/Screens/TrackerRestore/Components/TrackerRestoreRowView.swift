//
//  TrackerRestoreRowView.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import SwiftUI
import Kingfisher

// one queue row. icon/message vocabulary mirrors DetailsMetadataRefreshPill's
// for the same states, so a reader who has seen one recognises the other.
// the row itself carries its own controls and navigates nowhere, so it keeps
// .regular glass without .interactive() - see docs/design.md §2. everything
// inside stays flat - glass cannot sample glass, so no inner state gets a
// background of its own.
//
// idle and searching are each one big tappable centre, not a text link
// beside a disabled button - there is exactly one thing to do in either
// state. once results exist, up to Layout.previewCount show inline as
// SourceCards, the same carousel SourcePresetRow uses; the chevron opens
// MigrationCandidatePicker for the rest, and for editing the query
struct TrackerRestoreRowView: View {
    let row: MigrationRow<TrackerImportEntry>
    // which tracker this whole session is pulling from - needed only to map
    // row.entry.remoteStatus (that tracker's own raw vocabulary) to Status
    // for SavedSummary. every row in a session shares one tracker, so this
    // is a session-level fact handed down rather than something the row
    // itself carries
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

                // lives beside the title it belongs to, not a second row of
                // its own - the carousel below has results, not a headline.
                // gone once saved - the picked candidate is a fact by then,
                // not a choice, and this chevron is what opens the picker a
                // reader could use to change it
                if case .found = row.match, row.outcome != .saved {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                        .tappable { showingPicker = true }
                }
            }

            // one phase swap, one animation key - docs/design.md §1: transition
            // per branch, .settle on the surviving container, never a bare Group.
            // precheckMatched short-circuits the match switch entirely - these
            // rows were never searched, and match stays .idle for them
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

                    case let .found(candidates, selected):
                        // once saved this is a one-and-done operation: the
                        // commit already created a series, fetched its
                        // chapters and linked the tracker, so the carousel's
                        // own onSelect tap - which would otherwise just swap
                        // a preference - is what undoes real work here.
                        // shown instead as the flat, non-interactive summary
                        // AlreadyLinkedPrompt uses for the same reason
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
            }

            // a failed attempt states why before offering Skip - the reader
            // decides whether it's worth a re-search or just moving on. a
            // skipped row keeps stating the same reason, since it is the
            // only record of why this one never made it in
            if let reason = row.outcome?.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.warningText)
                    .lineLimit(2)
            }

            // one Skip, in one place, regardless of which dead end put the
            // row here - a found-but-failed save, a search that came back
            // with nothing, or a search that failed outright all land on
            // the same bottom-trailing slot. the dead-end ContentUnavailableViews
            // above offer only Retry, not their own Skip, so there is exactly
            // one uniform way to give up on a row.
            //
            // row.saving is its own branch here rather than folded into
            // canSave - canSave is deliberately false while saving (so a
            // second tap can't fire mid-request), which used to mean this
            // whole row disappeared the moment Save was tapped and nothing
            // was left on screen to say a save was in flight at all
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
        // one animation key per state this row tracks, on the one container
        // that survives every phase swap - covers the header's icon/chevron,
        // the phase content below, the failure-reason line, and the bottom
        // action row all at once, rather than scattering the same three
        // modifiers across each child that happens to read one of them
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

    // the same tinted-capsule action StartButton and DetailsContinue use,
    // scaled to a row rather than a whole screen - trailing-aligned, not a
    // borderedProminent pill that belongs to no other surface in this app
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

    // the same shape as Save, muted-tinted rather than brand or warning -
    // skipping is a deliberate choice, not a failure, and per docs/design.md
    // §18 an alarm colour belongs to an error state, not to the reader's own
    // decision to move on from one
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

    // a symbol never crossfades - it draws. same rule DetailsMetadataRefreshPill's
    // Icon follows: .symbolEffect(.drawOn) on entry, Reduce Motion falls back
    // to opacity, and the busy state is progress.indicator + a continuous spin
    // rather than a bare ProgressView with no stroke to draw out of
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

    // nothing to do here at all - this exact tracker entry is already linked
    // to a series in the library, found before any search ran. no controls,
    // matching the flat, non-interactive centre every other terminal state uses
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

    // a mix of both halves of what a saved row knows, stated rather than
    // offered - no tap target: the candidate's own cover (what the source
    // showed for it - nothing here reads back the library's own final
    // pooled cover, since the commit never hands its seriesId back), and the
    // tracker's own progress/status, as a Badge pill (the same component
    // DetailsSources' own DISCONNECTED tag uses) and a real progress bar
    // (matching DetailsDisambiguation's own read/total ProgressView,
    // .tint(.brand) included) rather than plain text. title is deliberately
    // not repeated - the row's own header above already carries
    // row.entry.title for every state, saved included, and restating it
    // here is the redundancy CLAUDE.md's own rule warns against
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

    // two branches rather than one String built with `??` - a coalesce into
    // plain String is what already broke inflection markup once on this
    // screen (docs/findings.md), since LocalizedStringKey parsing only
    // applies to a literal handed to Text(_:) directly
    @ViewBuilder
    private var ProgressText: some View {
        if let total = row.entry.totalChapters, total > 0 {
            Text("\(row.entry.progress) of \(total)")
        } else {
            Text("^[\(row.entry.progress) chapter](inflect: true) read")
        }
    }

    // bigger than a list-row thumbnail on purpose - this is the one piece of
    // real artwork a saved row has left once the carousel is gone, so it
    // carries more of the card's visual weight than an icon-scale image would
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

    // nothing has happened yet - the whole centre is the one thing to do
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

    // skeleton cards rather than a spinner - the same SourcePresetRow.Skeleton
    // shape, so a row mid-search previews what it is about to become instead
    // of blocking on a bare ProgressView
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

    // Retry is the only action a dead end offers inline - Skip lives in the
    // one bottom-trailing slot every row shares, not duplicated per state
    private var DeadEndActions: some View {
        Button("Retry") { onSearch(nil) }
    }

    // up to Layout.previewCount candidates, inline - the chevron beside the
    // row's own title is the one way to see the rest, never a count
    // truncated silently. the selected candidate's title is not repeated
    // here - the row's own title above already says it - so this line names
    // the source it came from instead, or how many matches there are
    private func ResultsCarousel(_ candidates: [MigrationCandidate], selected: MigrationCandidate?) -> some View {
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

                        SourceCard(stub: candidate.stub, referer: source?.descriptor.referer, selected: candidate == selected)
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
                .frame(width: Layout.sourceIconSize, height: Layout.sourceIconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
                .padding(dimensions.spacing.space4)
        }
    }
}

// MARK: - Previews

// stepped one at a time rather than all at once - the same shape
// DetailsSources' own SourcesPreview uses, and for the same reason: these
// states occupy the same row in practice, one after another, so a Previous/
// Next pair over a single live row shows what a reader actually sees rather
// than a static gallery of all of them side by side
#if DEBUG
private struct RowPreview: View {
    @State private var index = 0

    private static let source = AtsumaruSource(network: NetworkService())
    private static let sourcesBySlug: [String: Source] = [source.descriptor.slug: source]

    private static func entry(_ id: Int64, _ title: String) -> TrackerImportEntry {
        TrackerImportEntry(id: id, title: title, cover: nil, progress: 42, remoteStatus: "CURRENT", totalChapters: nil)
    }

    private static func candidate(_ slug: String, _ title: String) -> MigrationCandidate {
        MigrationCandidate(sourceSlug: source.descriptor.slug, stub: SeriesStub(slug: slug, title: title, cover: nil))
    }

    // genuinely ambiguous: none of these titles is an exact match for the
    // entry, which is exactly what LiveTrackerRestoreSearcher needs to leave
    // `selected` nil rather than auto-picking one
    private static let ambiguous = [candidate("a", "Solo Leveling: Ragnarok"), candidate("b", "Solo Leveling (Volume)"), candidate("c", "Only I Level Up")]
    private static let exact = [candidate("a", "Chainsaw Man"), candidate("b", "Chainsaw Man: Volume 1")]

    private static let states: [(name: String, row: MigrationRow<TrackerImportEntry>)] = [
        ("Idle", MigrationRow<TrackerImportEntry>(entry: entry(1, "Solo Leveling"))),
        ("Already linked", MigrationRow<TrackerImportEntry>(entry: entry(11, "Vagabond"), precheckMatched: true)),
        ("Searching", MigrationRow<TrackerImportEntry>(entry: entry(2, "Chainsaw Man"), match: .searching)),
        ("Found, ambiguous", MigrationRow<TrackerImportEntry>(entry: entry(3, "Solo Leveling"), match: .found(ambiguous, selected: nil))),
        // one candidate is an exact title match among alternates -
        // LiveTrackerRestoreSearcher auto-selects it, so the fixture does
        // too rather than leaving the row inconsistent with real search
        // behaviour
        ("Found, exact match auto-selected", MigrationRow<TrackerImportEntry>(entry: entry(4, "Chainsaw Man"), match: .found(exact, selected: exact[0]))),
        ("Saving", MigrationRow<TrackerImportEntry>(entry: entry(5, "Chainsaw Man"), match: .found(exact, selected: exact[0]), saving: true)),
        (
            "Saved",
            MigrationRow<TrackerImportEntry>(
                // a real total, unlike the other fixtures' - SavedSummary's
                // "N of total" branch has nothing else to preview it with
                entry: TrackerImportEntry(id: 6, title: "Chainsaw Man", cover: nil, progress: 97, remoteStatus: "CURRENT", totalChapters: 156),
                match: .found(exact, selected: exact[0]),
                outcome: .saved
            )
        ),
        ("Not found", MigrationRow<TrackerImportEntry>(entry: entry(7, "A Fabricated Title"), match: .notFound)),
        ("Search failed", MigrationRow<TrackerImportEntry>(entry: entry(8, "One Piece"), match: .failed("Every source failed to respond."))),
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
        )
    ]

    private var state: (name: String, row: MigrationRow<TrackerImportEntry>) { Self.states[index] }

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

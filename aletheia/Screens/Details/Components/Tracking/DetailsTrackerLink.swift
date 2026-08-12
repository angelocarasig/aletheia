//
//  DetailsTrackerLink.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI
import Kingfisher

// picking which entry on a service this series is.
//
// staged rather than instant-apply, and nothing is preselected even when one
// result comes back alone: linking writes to a public list and can overwrite
// somebody's progress, so it never happens without a deliberate tap. the same
// reasoning DetailsDisambiguation is built on, and the same shape
struct DetailsTrackerLink: View {
    let tracker: Tracker
    let seriesTitle: String
    // what is already linked, so re-linking a service shows what it would replace
    let existing: DetailsTracking.Link?
    let adult: Bool
    // how far this app has you read, shown beside the service's own number
    let localProgress: Int
    let scoreFormat: ScoreFormat
    var onSearch: (String) async throws -> [TrackerCandidate]
    // the reader's entry for one media, fetched only when they open it
    var onLoadEntry: (Int64) async throws -> TrackerEntry
    var onCatchUp: (Int) -> Void
    var onPushLocal: () -> Void
    // remote entries already spoken for by another series in the library
    var onConflicts: () async -> [Int64: String]
    // a pasted link or a bare id, for the entry search cannot reach
    var onResolve: (String) async -> TrackerCandidate?
    var onCommit: (TrackerCandidate, TrackerUpdate) async throws -> Void
    // reached only after a link has landed on this screen, where the commit has
    // become "Synced" and tapping it again is how the reader backs out
    var onUnlink: (Bool) -> Void
    var onCancel: () -> Void
    // passed through to the candidate screen this pushes - off inside the
    // add-to-library flow, where a fresh row has nothing to reconcile
    var reconciles: Bool = true

    @Environment(\.dimensions) private var dimensions

    @State private var query = ""
    @State private var results: [TrackerCandidate] = []
    @State private var opened: TrackerCandidate?
    @State private var phase: LoadPhase = .pending
    @State private var failure: Failure?
    @State private var search: Task<Void, Never>?
    @State private var conflicts: [Int64: String] = [:]

    private enum Layout {
        // wider than a thumbnail now that the row carries three text blocks -
        // the artwork sets the row's height and the text decides how far past it
        static let coverWidth: CGFloat = 84
        static let coverAspect: CGFloat = 11 / 16
        static let border: CGFloat = 2
        static let titleLines = 3
        static let authorLines = 2
        // two, not four: anyone opening this sheet already knows the plot - it is
        // why they are linking it - and four lines was the tallest and least
        // deciding block on the row
        static let synopsisLines = 2
        // context, not a deciding fact, so it sits under everything else
        static let synopsisOpacity: Double = 0.7
        static let placeholderOpacity: Double = 0.1
        // enough to drop the row out of the scan without hiding it: it is still a
        // legitimate pick when the reader is correcting the OTHER series' link
        static let claimedOpacity: Double = 0.55
        static let settle: Animation = .smooth(duration: 0.2)
        // long enough that typing a title does not fire a request per keystroke,
        // short enough that stopping feels like it answered immediately. also
        // what keeps anilist inside 30 requests a minute while a reader types
        static let debounce: Duration = .milliseconds(400)
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle(existing == nil ? "Link to \(tracker.name)" : "Change Link")
                .navigationSubtitle(Text(subtitle))
                .navigationBarTitleDisplayMode(.inline)
                .containerBackground(.clear, for: .navigation)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", action: onCancel)
                    }
                }
                // the row opens the entry rather than selecting it: what decides
                // a link is the reader's own standing on that entry, and a
                // fifty-row list cannot carry fifty of those
                .navigationDestination(item: $opened) { candidate in
                    DetailsTrackerCandidate(
                        tracker: tracker,
                        candidate: candidate,
                        localProgress: localProgress,
                        conflict: conflicts[candidate.id],
                        scoreFormat: scoreFormat,
                        reconciles: reconciles,
                        onLoad: { try await onLoadEntry(candidate.id) },
                        onCommit: onCommit,
                        onUnlink: onUnlink,
                        onCatchUp: onCatchUp,
                        onPushLocal: onPushLocal,
                        // the same exit the list behind it offers, so leaving is
                        // one tap from either page rather than a pop and then a
                        // Cancel
                        onClose: onCancel
                    )
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // seeded from the title the reader sees, which is the one they would
            // have typed. the first search runs without them asking
            query = seriesTitle
            conflicts = await onConflicts()
            await run(seriesTitle)
        }
        .onChange(of: query) { _, text in
            schedule(text)
        }
    }

    private var subtitle: String {
        if let existing {
            return "Currently \(existing.remoteTitle)"
        }
        return seriesTitle
    }

    // MARK: Content

    private var Content: some View {
        VStack(spacing: dimensions.spacing.space12) {
            Searchbar(searchText: $query, placeholder: "Search \(tracker.name)")
                .padding(.horizontal, dimensions.screenMargin)

            ZStack {
                switch phase {
                case .content:
                    Rows.transition(.opacity)
                case .empty:
                    Nothing.transition(.opacity)
                case .failed:
                    Unavailable.transition(.opacity)
                default:
                    SheetSkeleton(rows: 5).transition(.opacity)
                }
            }
            .animation(.settle, value: phase)
        }
        .padding(.top, dimensions.spacing.space8)
    }

    private var Rows: some View {
        ScrollView {
            LazyVStack(spacing: dimensions.spacing.space8) {
                ForEach(results) { candidate in
                    Row(candidate)
                        .tappable { opened = candidate }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var Nothing: some View {
        ContentUnavailableView.search(text: query)
    }

    @ViewBuilder
    private var Unavailable: some View {
        if let failure {
            ContentUnavailableView {
                Label(failure.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.message)
            } actions: {
                if failure.isRetryable {
                    Button("Try Again") { schedule(query, immediately: true) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    // top-aligned throughout, and nothing pinned to the bottom. metadata anchored
    // to the base of a row whose height comes from the artwork floats sixty
    // points below anything it describes when the entry is thin, and empty space
    // under a stack reads as air where the same space inside one reads as a
    // missing element
    private func Row(_ candidate: TrackerCandidate) -> some View {
        let clash = conflicts[candidate.id]

        return HStack(alignment: .top, spacing: dimensions.spacing.space12) {
            Cover(candidate)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                HStack(alignment: .top, spacing: dimensions.spacing.space8) {
                    // three lines and the priority, because the title is what
                    // actually separates a work from its own colour edition -
                    // truncating it mid-word to make room for a year pill spends
                    // the deciding field on the least deciding one
                    Text(candidate.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(Layout.titleLines)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Marks(candidate)
                }

                if let authors = candidate.authors, !authors.isEmpty {
                    Text(authors)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.muted)
                        .lineLimit(Layout.authorLines)
                }

                if let synopsis = candidate.synopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted.opacity(Layout.synopsisOpacity))
                        .lineLimit(Layout.synopsisLines)
                        .multilineTextAlignment(.leading)
                }

                Meta(candidate)

                // the highest-value thing on the row and the only fact the app
                // alone can know: two library rows aimed at one remote entry push
                // against each other forever, and the entry itself never says
                // which one is winning. named, because a bare warning would send
                // the reader to another screen to learn what they need here
                // a badge rather than a warning line: this is not a fault, it
                // is a FACT about the reader's own library - that entry is spoken
                // for by a series they already have. the neutral tone says so
                // without implying they did something wrong, and the series name
                // sits beside it in the app's own voice rather than the service's
                if let clash {
                    HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space4) {
                        Badge(text: "IN YOUR LIBRARY", tone: .neutral, size: .compact)

                        Text(clash)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, dimensions.spacing.space2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, dimensions.spacing.space2)
        }
        .padding(dimensions.spacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous)
        )
        .contentShape(.rect)
        // faded as a set rather than per element: everything on a claimed row is
        // equally less relevant, and dimming only the text would leave the cover
        // at full strength pulling the eye to the row the reader is least likely
        // to want. still selectable - they may be fixing the other link
        .opacity(clash == nil ? 1 : Layout.claimedOpacity)
        .accessibilityHint(clash == nil ? "Opens this entry" : "Already linked to \(clash ?? ""). Opens this entry")
    }

    // year is text rather than a pill: a date is not a state, and giving it pill
    // weight put it in competition with the one mark that is. the chapter count
    // is simply absent when null - permanent and normal for anything still
    // publishing, and the ONGOING mark two lines up already says so
    @ViewBuilder
    private func Meta(_ candidate: TrackerCandidate) -> some View {
        let year = candidate.year
        let chapters = candidate.totalChapters.flatMap { $0 > 0 ? $0 : nil }

        Group {
            if let year, let chapters {
                Text("\(String(year)) · ^[\(chapters) chapter](inflect: true)")
            } else if let chapters {
                Text("^[\(chapters) chapter](inflect: true)")
            } else if let year {
                Text(String(year))
            }
        }
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(.muted)
        .lineLimit(1)
        .padding(.top, dimensions.spacing.space2)
    }

    @ViewBuilder
    private func Marks(_ candidate: TrackerCandidate) -> some View {
        HStack(spacing: dimensions.spacing.space4) {
            // the classic misfire is linking the light novel to the manga -
            // same title, same author, same year, often the same cover art. it
            // only appears when the answer is surprising, since manga is the
            // assumption every reader already brings
            if let format = candidate.format {
                Badge(text: format.uppercased(), tone: .warning, size: .compact)
            }

            if candidate.adult {
                Badge(text: "ADULT", tone: .danger, size: .compact)
            }

            if candidate.status != .Unknown {
                Badge(
                    text: candidate.status.label.uppercased(),
                    tone: tone(for: candidate.status),
                    size: .compact
                )
            }
        }
        .fixedSize()
    }

    private func tone(for publication: Publication) -> Palette.Tone {
        switch publication {
        case .Ongoing: .success
        case .Completed: .brand
        case .Hiatus: .warning
        case .Cancelled: .danger
        case .Unknown: .neutral
        }
    }

    private func Cover(_ candidate: TrackerCandidate) -> some View {
        KFImage(candidate.cover)
            .resizable()
            .placeholder {
                Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
            }
            .fade(duration: 0.2)
            .scaledToFill()
            .frame(
                width: Layout.coverWidth,
                height: Layout.coverWidth / Layout.coverAspect
            )
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8, style: .continuous))
    }

    // MARK: Searching

    private func schedule(_ text: String, immediately: Bool = false) {
        search?.cancel()
        search = Task {
            if !immediately {
                try? await Task.sleep(for: Layout.debounce)
                guard !Task.isCancelled else { return }
            }
            await run(text)
        }
    }

    private func run(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            phase = .empty
            return
        }

        phase = results.isEmpty ? .pending : phase
        failure = nil

        // a pasted link names one entry outright. searching for its digits finds
        // nothing, so the id path is tried first and only falls through when it
        // is not an id at all
        if Tracker.remoteId(in: trimmed) != nil {
            if let resolved = await onResolve(trimmed) {
                guard !Task.isCancelled else { return }
                results = [resolved]
                phase = .content
                return
            }
        }

        do {
            let found = try await onSearch(trimmed)
            guard !Task.isCancelled else { return }

            results = found
            phase = found.isEmpty ? .empty : .content
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failure = Failure(error, fallback: "Couldn't Search")
            phase = .failed
        }
    }
}

// MARK: - Previews

private extension TrackerCandidate {
    // covers are left nil on purpose: a preview that reaches the network renders
    // differently depending on whether it did, which is the one thing a specimen
    // must not do
    static let samples: [TrackerCandidate] = [
        .init(
            id: 101177,
            title: "Kanojo mo Kanojo",
            year: 2020,
            totalChapters: 122,
            status: .Completed,
            authors: "Hiroyuki",
            synopsis: "Naoya Mukai has been in love with his childhood friend Saki for years, and when she finally accepts his confession he could not be happier. Then Nagisa Minase confesses to him too, and rather than turn her down he proposes something no one asked for."
        ),
        .init(
            id: 132182,
            title: "Kanojo mo Kanojo: Kanojo ga Kanojo",
            year: 2023,
            totalChapters: nil,
            status: .Ongoing,
            authors: "Hiroyuki, Kazuki Yoshida",
            synopsis: "A spin-off following the side characters after the events of the main series."
        ),
        .init(
            id: 45012,
            title: "Kanojo mo Kanojo: The Novel",
            year: 2021,
            totalChapters: 4,
            status: .Completed,
            authors: "Hiroyuki",
            synopsis: "A light novel adaptation.",
            format: "Novel"
        ),
        // no author and no synopsis - the row has to survive both being absent
        .init(
            id: 30013,
            title: "Girlfriend, Girlfriend: Colour Edition",
            year: 2021,
            totalChapters: 122,
            status: .Completed
        ),
        .init(
            id: 88991,
            title: "Kanojo mo Kanojo Anthology",
            year: 2022,
            totalChapters: 8,
            status: .Completed,
            adult: true,
            authors: "Various",
            synopsis: "A short collection by guest artists."
        )
    ]
}

private struct LinkPreview: View {
    enum Outcome {
        case results
        case slow
        case empty
        case failing
    }

    var tracker: Tracker = .anilist
    var outcome: Outcome = .results
    var existing: DetailsTracking.Link?
    var conflicts: [Int64: String] = [:]

    var body: some View {
        DetailsTrackerLink(
            tracker: tracker,
            seriesTitle: "Kanojo mo Kanojo",
            existing: existing,
            adult: false,
            localProgress: 42,
            scoreFormat: .point10,
            onSearch: { query in
                switch outcome {
                case .results:
                    return TrackerCandidate.samples
                case .slow:
                    // long enough to sit in the skeleton and look at it
                    try await Task.sleep(for: .seconds(30))
                    return TrackerCandidate.samples
                case .empty:
                    return []
                case .failing:
                    throw TrackerError.throttled(retryAfter: 60)
                }
            },
            onLoadEntry: { id in
                TrackerEntry(
                    remoteId: id,
                    title: "Kanojo mo Kanojo",
                    totalChapters: 122,
                    entryId: 900,
                    status: .reading,
                    progress: 38,
                    score: 80
                )
            },
            onCatchUp: { _ in },
            onPushLocal: {},
            onConflicts: { conflicts },
            onResolve: { _ in nil },
            onCommit: { _, _ in },
            onUnlink: { _ in },
            onCancel: {}
        )
    }
}

#Preview("Results") {
    LinkPreview()
}

#Preview("Already linked elsewhere") {
    LinkPreview(conflicts: [101177: "Girlfriend, Girlfriend"])
}

// the state the sheet opens in every time, and the one a debounce spends most
// of its life in
#Preview("Searching") {
    LinkPreview(outcome: .slow)
}

#Preview("Nothing found") {
    LinkPreview(outcome: .empty)
}

// a throttle rather than an outage, because that is the failure this sheet will
// actually meet - anilist runs at thirty requests a minute
#Preview("Failed") {
    LinkPreview(outcome: .failing)
}

// re-linking states what it would replace, or the reader is committing over
// something they cannot see
#Preview("Change link") {
    LinkPreview(
        existing: .init(
            id: 1,
            tracker: .anilist,
            remoteId: 101177,
            remoteTitle: "Girlfriend, Girlfriend",
            status: .reading,
            progress: 42,
            total: 122,
            score: 80,
            scoreFormat: .point10,
            syncedDate: .distantPast,
            attemptedDate: .distantPast,
            failureReason: nil
        )
    )
}

#Preview("MyAnimeList") {
    LinkPreview(tracker: .myAnimeList)
}

#Preview("Dark") {
    LinkPreview()
        .environment(\.colorScheme, .dark)
}

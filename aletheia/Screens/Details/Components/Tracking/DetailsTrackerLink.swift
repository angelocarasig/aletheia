//
//  DetailsTrackerLink.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Kingfisher
import SwiftUI

struct DetailsTrackerLink: View {
    let tracker: Tracker
    let seriesTitle: String
    let existing: DetailsTracking.Link?
    let adult: Bool
    let localProgress: Int
    let scoreFormat: ScoreFormat
    var onSearch: (String) async throws -> [TrackerCandidate]
    // awaited rather than re-run - opening mid-flight (the setup flow already
    // searches before the sheet opens) waits on the request already in the
    // air instead of starting a second one. nil means nothing was prefetched
    // or the prefetch failed, and this searches as usual
    var onPrefetched: () async -> DetailsComposer.Tracking.Search? = { nil }
    var onLoadEntry: (Int64) async throws -> TrackerEntry
    var onCatchUp: (Int) -> Void
    var onPushLocal: () -> Void
    var onConflicts: () async -> [Int64: String]
    var onResolve: (String) async -> TrackerCandidate?
    var onCommit: (TrackerCandidate, TrackerUpdate) async throws -> Void
    var onUnlink: (Bool) -> Void
    var onCancel: () -> Void
    var reconciles: Bool = true

    @Environment(\.dimensions) private var dimensions

    @State private var query = ""
    @State private var results: [TrackerCandidate] = []
    @State private var opened: TrackerCandidate?
    @State private var phase: LoadPhase = .pending
    @State private var failure: Failure?
    @State private var search: Task<Void, Never>?
    @State private var conflicts: [Int64: String] = [:]
    @State private var seeded = false

    private enum Layout {
        static let coverWidth: CGFloat = 84
        static let coverAspect: CGFloat = 11 / 16
        static let border: CGFloat = 2
        static let titleLines = 3
        static let authorLines = 2
        static let synopsisLines = 2
        static let synopsisOpacity: Double = 0.7
        static let placeholderOpacity: Double = 0.1
        // both a conflicted row and a novel result stay pickable - dimmed,
        // not hidden, since the reader may genuinely mean either one
        static let sidelinedOpacity: Double = 0.55
        static let settle: Animation = .smooth(duration: 0.2)
        // also keeps AniList inside its 30-requests-a-minute limit while typing
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
                        onClose: onCancel
                    )
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            query = seriesTitle

            if let prefetched = await onPrefetched() {
                conflicts = prefetched.conflicts
                results = prefetched.results
                phase = prefetched.results.isEmpty ? .empty : .content
            } else {
                conflicts = await onConflicts()
                await run(seriesTitle)
            }

            seeded = true
        }
        .onChange(of: query) { _, text in
            // seeding `query` above fires this too - without the guard, every
            // open ran the same search twice: once directly, once again
            // 400ms later
            guard seeded else { return }
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

    private func Row(_ candidate: TrackerCandidate) -> some View {
        let clash = conflicts[candidate.id]
        let sidelined = clash != nil || candidate.isNovel

        return HStack(alignment: .top, spacing: dimensions.spacing.space12) {
            Cover(candidate)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                HStack(alignment: .top, spacing: dimensions.spacing.space8) {
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
        .opacity(sidelined ? Layout.sidelinedOpacity : 1)
        .accessibilityHint(hint(clash: clash, novel: candidate.isNovel))
    }

    private func hint(clash: String?, novel: Bool) -> String {
        var parts: [String] = []
        if let clash { parts.append("Already linked to \(clash).") }
        if novel { parts.append("Not a comic.") }
        parts.append("Opens this entry")
        return parts.joined(separator: " ")
    }

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
            // same title, author and year, often the same cover art
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

extension TrackerCandidate {
    fileprivate static let samples: [TrackerCandidate] = [
        .init(
            id: 101177,
            title: "Kanojo mo Kanojo",
            year: 2020,
            totalChapters: 122,
            status: .Completed,
            authors: "Hiroyuki",
            synopsis:
                "Naoya Mukai has been in love with his childhood friend Saki for years, and when she finally accepts his confession he could not be happier. Then Nagisa Minase confesses to him too, and rather than turn her down he proposes something no one asked for."
        ),
        .init(
            id: 132182,
            title: "Kanojo mo Kanojo: Kanojo ga Kanojo",
            year: 2023,
            totalChapters: nil,
            status: .Ongoing,
            authors: "Hiroyuki, Kazuki Yoshida",
            synopsis:
                "A spin-off following the side characters after the events of the main series."
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
        ),
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

#Preview("Searching") {
    LinkPreview(outcome: .slow)
}

#Preview("Nothing found") {
    LinkPreview(outcome: .empty)
}

#Preview("Failed") {
    LinkPreview(outcome: .failing)
}

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
            failureReason: nil,
            queued: false
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

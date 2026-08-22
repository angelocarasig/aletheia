//
//  DetailsTracking.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Kingfisher
import SwiftUI

struct DetailsTracking: View {
    let accounts: [Tracker]
    let links: [Link]
    let localProgress: Int
    var showsHeader: Bool = true
    // tracking requires library membership (trackers.md Q6). shown dimmed
    // and inert rather than hidden off-library - a section that vanishes
    // reads as broken to a reader with accounts already connected
    var enabled: Bool = true
    // connected but out of road until the reader signs in again - AniList's
    // token expiring and MyAnimeList's refresh token being refused both land
    // here
    var needingSignIn: Set<Tracker> = []
    // per service, not per series - a single section-wide flag meant a push
    // on either account spun both rows
    let syncing: Set<Tracker>
    var onLink: (Tracker) -> Void
    var onOpen: (Link) -> Void
    var onConnect: () -> Void
    var onRetry: (Link) -> Void = { _ in }
    // neither takes a tracker - both writes are already series-wide: the
    // mark covers every source, the push goes to every linked service
    var onCatchUp: (Int) -> Void = { _ in }
    var onPushLocal: () -> Void = {}
    // off inside the add-to-library flow - that screen is for choosing
    // links, and a banner offering to mark chapters read mid-flow is a
    // write nobody went there to make
    var reconciles: Bool = true
    var matches: [Tracker: DetailsComposer.Tracking.Match] = [:]
    var linking: Set<Tracker> = []
    var onAutoLink: (Tracker, TrackerCandidate) -> Void = { _, _ in }

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirming: TrackerReconcile?

    private enum Layout {
        static let tile: CGFloat = 44
        static let fillOpacity: Double = 0.05
        static let settle: Animation = .smooth(duration: 0.3)
        static let disabledOpacity: Double = 0.4
        static let skeletonWidth: CGFloat = 140
        static let skeletonHeight: CGFloat = 10
        // fillOpacity above is for surfaces behind text, and at 0.05 was too
        // faint to be the skeleton content itself - it simply couldn't be seen
        static let skeletonOpacity: Double = 0.1
        static let coverWidth: CGFloat = 30
        static let coverHeight: CGFloat = 44
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            if showsHeader {
                SectionHeader("Tracking")
            }

            if services.isEmpty {
                Empty
            } else {
                Disagreement

                VStack(spacing: dimensions.spacing.space16) {
                    ForEach(services) { tracker in
                        Row(tracker)
                    }
                }
            }

            if !enabled {
                Text("Add this to your library to track it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(enabled ? 1 : Layout.disabledOpacity)
        .disabled(!enabled)
        .animation(Layout.settle, value: enabled)
        .animation(Layout.settle, value: links)
        .animation(Layout.settle, value: accounts)
        .animation(Layout.settle, value: reconcile)
        .animation(Layout.settle, value: localProgress)
        .trackerReconcile(
            $confirming,
            subject: pushSubject,
            onCatchUp: onCatchUp,
            onPushLocal: onPushLocal
        )
    }

    // MARK: Disagreement

    // brand, not the default warning tone - amber stays reserved for
    // SectionFailure directly below this same section, which IS a failure;
    // sharing the colour would make an offer read as a fault
    @ViewBuilder
    private var Disagreement: some View {
        if let reconcile = reconcile {
            Group {
                switch reconcile {
                case .pull(let chapter):
                    if let only = links.first, links.count == 1 {
                        Banner(
                            "\(only.tracker.name) is at chapter \(chapter)",
                            message: "Mark chapters up to \(chapter) as read here",
                            systemImage: "icloud.and.arrow.down",
                            tone: .brand,
                            action: { confirming = reconcile }
                        )
                    } else {
                        Banner(
                            "Your trackers are at chapter \(chapter)",
                            message: "Mark chapters up to \(chapter) as read here",
                            systemImage: "icloud.and.arrow.down",
                            tone: .brand,
                            action: { confirming = reconcile }
                        )
                    }
                case .push(let chapter):
                    Banner(
                        "You're at chapter \(chapter) here",
                        message: "Update \(pushSubject) to match",
                        systemImage: "icloud.and.arrow.up",
                        tone: .brand,
                        action: { confirming = reconcile }
                    )
                }
            }
            .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
        }
    }

    // pull wins where both are true at once - one service ahead, another
    // behind. accepting the pull enqueues a push for every laggard, so the
    // second direction resolves on its own without a second banner
    private var reconcile: TrackerReconcile? {
        guard reconciles, let furthest = links.map(\.progress).max() else { return nil }

        if furthest > localProgress { return .pull(furthest) }

        // a queued row is excluded, not just checked for a slack of one
        // chapter - otherwise, in the seconds between accepting a pull and
        // the enqueued push landing, the banner would flip from pull to
        // push, offering the reader the work it just did
        let stale = links.filter {
            $0.behind(localProgress) && !$0.queued && !syncing.contains($0.tracker)
        }
        if !stale.isEmpty { return .push(localProgress) }
        return nil
    }

    private var pushSubject: String {
        links.count == 1 ? (links.first?.tracker.name ?? "your trackers") : "your trackers"
    }

    // the union of connected and linked services, not just accounts - a
    // deliberate sign-out leaves the link behind, and driving this off the
    // account list alone would drop a still-linked service off the screen
    // entirely, with nothing to act on. ordered by the enum, not either set,
    // so rows do not reshuffle when an account comes or goes
    private var services: [Tracker] {
        let linked = Set(links.map(\.tracker))
        return Tracker.allCases.filter { accounts.contains($0) || linked.contains($0) }
    }

    private func unavailable(_ tracker: Tracker) -> Bool {
        !accounts.contains(tracker) || needingSignIn.contains(tracker)
    }

    // not ContentUnavailableView - that sizes itself for an empty screen, and
    // this is one row's worth sitting between two sections that are full
    private var Empty: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Text("Connect an account to keep your lists in step with what you read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Connect")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, dimensions.spacing.space16)
                .frame(height: dimensions.touchTarget)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
                .tappable(action: onConnect)
        }
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    // MARK: Row

    @ViewBuilder
    private func Row(_ tracker: Tracker) -> some View {
        let link = links.first { $0.tracker == tracker }

        if let link {
            Content(tracker, link: link)
                .contentShape(.rect)
                .tappable { onOpen(link) }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens tracking options")
        } else {
            Content(tracker, link: nil)
                .animation(Layout.settle, value: matches[tracker])
        }
    }

    private func match(_ tracker: Tracker, link: Link?) -> DetailsComposer.Tracking.Match? {
        guard link == nil, !unavailable(tracker) else { return nil }
        return matches[tracker]
    }

    private func Content(_ tracker: Tracker, link: Link?) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Tile(tracker)

            if let match = match(tracker, link: link) {
                Cover(match)
            }

            Details(tracker, link: link)

            Spacer(minLength: 0)

            Trailing(tracker, link: link)
        }
    }

    @ViewBuilder
    private func Cover(_ match: DetailsComposer.Tracking.Match) -> some View {
        switch match {
        case .searching:
            CoverFrame { EmptyView() }
                .shimmer()

        case .found(let candidate):
            CoverFrame {
                if let cover = candidate.cover {
                    KFImage(cover)
                        .resizable()
                        .scaledToFill()
                }
            }

        case .unmatched:
            EmptyView()
        }
    }

    private func CoverFrame<Artwork: View>(@ViewBuilder _ artwork: () -> Artwork) -> some View {
        RoundedRectangle(cornerRadius: dimensions.radius.radius8)
            .fill(.primary.opacity(Layout.skeletonOpacity))
            .frame(width: Layout.coverWidth, height: Layout.coverHeight)
            .overlay { artwork() }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }

    private func Tile(_ tracker: Tracker) -> some View {
        Image(tracker.icon)
            .resizable()
            .scaledToFit()
            .frame(width: Layout.tile, height: Layout.tile)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
    }

    @ViewBuilder
    private func Details(_ tracker: Tracker, link: Link?) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
                Text(name(tracker, link: link))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                State(tracker, link: link)
            }

            Subtitle(tracker, link: link)

            if let link, unavailable(tracker) || link.failing {
                Trouble(tracker, link: link)
            }
        }
    }

    @ViewBuilder
    private func State(_ tracker: Tracker, link: Link?) -> some View {
        if link != nil, unavailable(tracker) || link?.failing == true {
            Badge(text: "SYNC FAILED", tone: .warning, size: .compact)
        } else if let status = link?.status {
            Badge(text: status.label.uppercased(), tone: status.tone, size: .compact)
        }
    }

    @ViewBuilder
    private func Subtitle(_ tracker: Tracker, link: Link?) -> some View {
        Group {
            if let link {
                if link.behind(localProgress) {
                    Text("\(localProgress) here · \(link.progress) on \(tracker.name)")
                } else if let synced = link.synced {
                    LiveRelative(date: synced) { relative in
                        Text("\(link.summary) · synced \(relative)")
                            .contentTransition(.numericText())
                            .animation(.default, value: relative)
                    }
                } else {
                    Text(link.summary)
                }
            } else if unavailable(tracker) {
                Text("Sign in again to keep tracking")
            } else if let match = match(tracker, link: link) {
                switch match {
                case .searching:
                    Capsule()
                        .fill(.primary.opacity(Layout.skeletonOpacity))
                        .frame(width: Layout.skeletonWidth, height: Layout.skeletonHeight)
                        .shimmer()
                        .accessibilityLabel("Searching \(tracker.name)")

                case .found(let candidate):
                    Text(facts(for: candidate))

                case .unmatched(let count) where count > 0:
                    Text("^[\(count) possible match](inflect: true)")

                case .unmatched:
                    Text("No matches found")
                }
            } else {
                Text("Not linked")
            }
        }
        .font(.caption2)
        .foregroundStyle(subtitleTint(tracker, link: link))
        .lineLimit(1)
    }

    // being behind used to tint this line amber too - once the banner
    // arrived that was the same fact stated three times (badge, line,
    // banner), so the line kept the numbers and gave up the colour
    private func subtitleTint(_ tracker: Tracker, link: Link?) -> AnyShapeStyle {
        if unavailable(tracker) && link == nil {
            AnyShapeStyle(.warningText)
        } else {
            AnyShapeStyle(.muted)
        }
    }

    // attemptedDate is the last-attempt date, not first-seen - one column
    // cannot honestly claim when a failure started
    @ViewBuilder
    private func Trouble(_ tracker: Tracker, link: Link) -> some View {
        if let reason = reason(tracker, link: link) {
            Group {
                if link.attemptedDate > .distantPast {
                    LiveRelative(date: link.attemptedDate) { relative in
                        Text("\(reason) Last tried \(relative).")
                    }
                } else {
                    Text(reason)
                }
            }
            .font(.caption2)
            .foregroundStyle(.warningText)
            .lineLimit(2)
        }
    }

    // account status outranks the push failure reason - a dead account is
    // WHY the push failed, so its own reason would name the symptom over
    // the cause
    private func reason(_ tracker: Tracker, link: Link) -> String? {
        if unavailable(tracker) { return "Sign in again to keep tracking." }
        return link.failureReason
    }

    @ViewBuilder
    private func Trailing(_ tracker: Tracker, link: Link?) -> some View {
        if unavailable(tracker) {
            // linked and unlinked both point at sign-in here - offering Link
            // would just fail, and a chevron into a screen that cannot help
            // is worse
            Glyph(for: tracker, link: link)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .tappable(action: onConnect)
                .accessibilityLabel("Sign in to \(tracker.name) again")
        } else if let link, link.failing, !syncing.contains(tracker) {
            Glyph(for: tracker, link: link)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .tappable { onRetry(link) }
                .accessibilityLabel("Retry syncing to \(tracker.name)")
        } else if case .found(let candidate)? = match(tracker, link: link),
            !syncing.contains(tracker)
        {
            HStack(spacing: dimensions.spacing.space8) {
                Circular("link", busy: linking.contains(tracker)) {
                    onAutoLink(tracker, candidate)
                }
                .accessibilityLabel("Link \(candidate.title) on \(tracker.name)")

                Circular("magnifyingglass") { onLink(tracker) }
                    .accessibilityLabel("Search \(tracker.name) for another entry")
            }
            .disabled(linking.contains(tracker))
        } else if link == nil, !syncing.contains(tracker) {
            Glyph(for: tracker, link: nil)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .tappable { onLink(tracker) }
                .accessibilityLabel("Link to \(tracker.name)")
        } else {
            Glyph(for: tracker, link: link)
                .accessibilityHidden(true)
        }
    }

    private func Glyph(for tracker: Tracker, link: Link?) -> some View {
        Image(systemName: glyph(for: tracker, link: link))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .contentTransition(.symbolEffect(.replace))
            // gated on this row's own service - left unconditional it spins
            // whatever glyph is in the slot, so two linked rows once sat
            // rotating their chevrons forever
            .symbolEffect(
                .rotate,
                options: .repeat(.continuous),
                isActive: syncing.contains(tracker) && !reduceMotion
            )
            .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
            // syncing arrives from an observation with no animation of its
            // own, so contentTransition has nothing to run inside without this
            .animation(.settle, value: syncing)
    }

    private func Circular(
        _ symbol: String,
        busy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: busy ? "progress.indicator" : symbol)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .symbolEffect(.rotate, isActive: busy)
            .frame(width: Layout.tile, height: Layout.tile)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
            .tappable(action: action)
    }

    private func name(_ tracker: Tracker, link: Link?) -> String {
        if let link { return link.remoteTitle }
        if case .found(let candidate)? = match(tracker, link: link) { return candidate.title }
        return tracker.name
    }

    private func facts(for candidate: TrackerCandidate) -> String {
        var parts: [String] = []
        if let year = candidate.year { parts.append(String(year)) }
        if let total = candidate.totalChapters { parts.append("\(total) chapters") }
        return parts.isEmpty ? "Match found" : parts.joined(separator: " · ")
    }

    private func glyph(for tracker: Tracker, link: Link?) -> String {
        if syncing.contains(tracker) { return "progress.indicator" }
        // must not share a glyph with the failing case below - a retry arrow
        // here would promise that tapping retries the sync, which would just
        // fail again for the same reason it failed the first time
        if unavailable(tracker) { return "person.crop.circle.badge.exclamationmark" }
        if link?.failing == true { return "arrow.clockwise" }
        return link == nil ? "link" : "chevron.right"
    }
}

// MARK: - Link

extension DetailsTracking {
    typealias Link = DetailsComposer.Tracking.Link
}

// MARK: - Previews

extension DetailsTracking.Link {
    fileprivate static func sample(
        _ tracker: Tracker = .anilist,
        title: String = "Girlfriend, Girlfriend",
        status: Status? = .reading,
        progress: Int = 42,
        total: Int? = 120,
        score: Int? = 80,
        format: ScoreFormat = .point10,
        synced: Date = .now.addingTimeInterval(-7200),
        failure: String? = nil
    ) -> Self {
        .init(
            id: Int64(tracker.hashValue),
            tracker: tracker,
            remoteId: 101177,
            remoteTitle: title,
            status: status,
            progress: progress,
            total: total,
            score: score,
            scoreFormat: format,
            syncedDate: synced,
            attemptedDate: .now.addingTimeInterval(-3600),
            failureReason: failure,
            queued: false
        )
    }
}

private struct TrackingPreview: View {
    var accounts: [Tracker] = [.anilist, .myAnimeList]
    var links: [DetailsTracking.Link] = []
    var localProgress = 42
    var syncing: Set<Tracker> = []
    var needingSignIn: Set<Tracker> = []
    var enabled = true
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.muted)

            DetailsTracking(
                accounts: accounts,
                links: links,
                localProgress: localProgress,
                enabled: enabled,
                needingSignIn: needingSignIn,
                syncing: syncing,
                onLink: { _ in },
                onOpen: { _ in },
                onConnect: {}
            )
        }
    }
}

#Preview("States") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            TrackingPreview(accounts: [], caption: "No account connected")

            TrackingPreview(enabled: false, caption: "Not in library - connected")

            TrackingPreview(
                links: [.sample()],
                enabled: false,
                caption: "Not in library - already linked"
            )

            TrackingPreview(caption: "Connected, nothing linked")

            TrackingPreview(
                links: [.sample()],
                caption: "One linked, one not"
            )

            TrackingPreview(
                links: [
                    .sample(), .sample(.myAnimeList, status: .completed, progress: 120, score: 90),
                ],
                localProgress: 120,
                caption: "Both linked"
            )

            TrackingPreview(
                links: [.sample()],
                syncing: [.anilist],
                caption: "Syncing"
            )

            TrackingPreview(
                accounts: [.myAnimeList],
                links: [.sample()],
                caption: "Signed out, still linked"
            )

            TrackingPreview(
                links: [.sample()],
                needingSignIn: [.anilist],
                caption: "Connected, token run out"
            )

            TrackingPreview(
                needingSignIn: [.anilist, .myAnimeList],
                caption: "Both need signing in, neither linked"
            )
        }
        .padding(16)
    }
    .background(.canvas)
}

#Preview("Trouble") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            TrackingPreview(
                links: [.sample(failure: "Sign in again to keep tracking.")],
                caption: "Failed, and the reason survives relaunch"
            )

            TrackingPreview(
                links: [.sample(progress: 38)],
                localProgress: 60,
                caption: "Local ahead: nothing is wrong, they simply disagree"
            )

            TrackingPreview(
                links: [.sample(progress: 41)],
                localProgress: 42,
                caption: "One behind: the ordinary gap before a push lands, so no warning"
            )

            TrackingPreview(
                links: [.sample(status: nil, total: nil, score: nil)],
                caption: "Ongoing work, unscored, no status yet"
            )
        }
        .padding(16)
    }
    .background(.canvas)
}

#Preview("Dark") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            TrackingPreview(accounts: [], caption: "No account connected")
            TrackingPreview(links: [.sample()], caption: "One linked, one not")
            TrackingPreview(
                links: [.sample(failure: "MyAnimeList refused the change.")],
                caption: "Failed"
            )
        }
        .padding(16)
    }
    .background(.canvas)
    .environment(\.colorScheme, .dark)
}

#Preview("Narrow") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            TrackingPreview(
                links: [.sample(title: "The Dangers in My Heart, Volume Twelve")],
                caption: "320pt"
            )
        }
        .padding(16)
    }
    .frame(width: 320)
    .background(.canvas)
}

#Preview("Live states") {
    @Previewable @State var step = 0

    let states: [(String, [Tracker], [DetailsTracking.Link], Set<Tracker>, Set<Tracker>)] = [
        ("No account connected", [], [], [], []),
        ("Connected, nothing linked", [.anilist, .myAnimeList], [], [], []),
        ("One linked", [.anilist, .myAnimeList], [.sample()], [], []),
        ("Pushing", [.anilist, .myAnimeList], [.sample()], [.anilist], []),
        ("Service is behind", [.anilist, .myAnimeList], [.sample(progress: 12)], [], []),
        (
            "Finished on the service", [.anilist, .myAnimeList],
            [.sample(status: .completed, progress: 122)], [], []
        ),
        (
            "Sync failed - retry beside it", [.anilist, .myAnimeList],
            [.sample(failure: "You're offline.")], [], []
        ),
        (
            "Token run out - sign in beside it", [.anilist, .myAnimeList], [.sample()], [],
            [.anilist]
        ),
        ("Signed out, still linked", [.myAnimeList], [.sample()], [], []),
    ]

    let current = states[step % states.count]

    return VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(step % states.count + 1) of \(states.count)")
                .font(.caption2)
                .foregroundStyle(.muted)

            Text(current.0)
                .font(.caption)
                .fontWeight(.semibold)
                .contentTransition(.opacity)
        }

        DetailsTracking(
            accounts: current.1,
            links: current.2,
            localProgress: 42,
            needingSignIn: current.4,
            syncing: current.3,
            onLink: { _ in },
            onOpen: { _ in },
            onConnect: {}
        )

        Button("Next state") { withAnimation(.settle) { step += 1 } }
            .buttonStyle(.glassProminent)
    }
    .padding(16)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(.canvas)
}

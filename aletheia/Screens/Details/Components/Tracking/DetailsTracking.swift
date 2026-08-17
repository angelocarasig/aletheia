//
//  DetailsTracking.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI
import Kingfisher

// what each connected service says about this series. one row per account, never
// more than two, and the two never consult each other - a failure on one is not a
// failure on the other, and neither arbitrates the other's numbers.
//
// note what is absent: no checkmark and no brand tint on a linked row. a link is
// a FACT, not a chosen preference, and the selection language reserves the brand
// checkmark for options the reader picked between. the absence of a badge is the
// signal that everything is fine. see docs/features/trackers.md §10
struct DetailsTracking: View {
    let accounts: [Tracker]
    let links: [Link]
    // where the reader has actually got to, so a row can say when it is behind
    let localProgress: Int
    // off inside the add-to-library flow, where the page it sits on is already
    // titled Trackers. the rows are the reusable part; the header belongs to a
    // section among other sections, which is not what that page is
    var showsHeader: Bool = true
    // tracking needs library membership (trackers.md Q6), and the section used to
    // render nothing at all off-library. a section that vanishes explains nothing
    // - the reader who owns two accounts and sees no tracking on a series reads it
    // as broken, which is exactly what happened. it shows, dimmed and inert, with
    // one line saying what would make it work
    var enabled: Bool = true
    // connected, but out of road until the reader signs in again - anilist's year
    // running out and myanimelist's refresh token being refused both land here
    var needingSignIn: Set<Tracker> = []
    // per service, not per series: one flag for the section meant a push on
    // either account span both rows
    let syncing: Set<Tracker>
    var onLink: (Tracker) -> Void
    // every action a linked row has - edit, catch up, change link, open, unlink -
    // lives behind this one tap rather than in a menu beside it. a row that is a
    // statement and a menu at the same time makes the reader choose which half
    // they meant before they know what is inside either
    var onOpen: (Link) -> Void
    var onConnect: () -> Void
    // both persistent conditions carry one, because both are "try that again"
    // with a different subject: the push, or the account behind it
    var onRetry: (Link) -> Void = { _ in }
    // the two halves of the banner. both writes are already series-wide - the
    // mark covers every source, the push enqueues every link and skips one that
    // is already at the number - so neither takes a tracker
    var onCatchUp: (Int) -> Void = { _ in }
    var onPushLocal: () -> Void = {}
    // off inside the add-to-library flow, the same way the candidate sheet turns
    // it off there: that screen is for choosing links, and a banner offering to
    // mark sixty chapters read mid-flow is a write nobody went there to make
    var reconciles: Bool = true
    // what the setup flow searched for before the reader looked. empty
    // everywhere else, which is what leaves the Details section untouched -
    // a row with no match here is the row that has always been here
    var matches: [Tracker: DetailsComposer.Tracking.Match] = [:]
    // which services are mid-link, so the button that started it spins and the
    // other rows stay live
    var linking: Set<Tracker> = []
    var onAutoLink: (Tracker, TrackerCandidate) -> Void = { _, _ in }

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirming: TrackerReconcile?

    private enum Layout {
        static let tile: CGFloat = 44
        static let fillOpacity: Double = 0.05
        static let settle: Animation = .smooth(duration: 0.3)
        // far enough down to read as unavailable at a glance, not so far that
        // the service names stop being legible - the section still has to say
        // WHAT is waiting for you
        static let disabledOpacity: Double = 0.4
        // sized to the subtitle it stands in for, so the row does not resize when
        // the search lands
        static let skeletonWidth: CGFloat = 140
        static let skeletonHeight: CGFloat = 10
        // fillOpacity above is for surfaces behind text and is far too faint to
        // BE the content - at 0.05 the skeleton rendered and simply could not be
        // seen. this is what the reader's own skeletons use
        static let skeletonOpacity: Double = 0.1
        // small deliberately: the cover is here to confirm the match is the
        // series already on screen, not to be looked at
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
        // dimmed AND inert. one without the other is the worse half of each: a
        // dimmed row that still responds is a lie, and a dead row at full
        // strength is a control that silently ignores you
        .opacity(enabled ? 1 : Layout.disabledOpacity)
        .disabled(!enabled)
        // the sentence is the state's own explanation, so it fades with it
        .animation(Layout.settle, value: enabled)
        .animation(Layout.settle, value: links)
        .animation(Layout.settle, value: accounts)
        // the banner arrives and leaves on its own terms: a mark or a push
        // resolves it while links are otherwise unchanged
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

    // one banner for the section rather than one per row, because both writes
    // are series-wide: marking up to the furthest service satisfies the nearer
    // one for free, and a push goes to every link at once. two banners would be
    // two taps for one reconciliation.
    //
    // brand rather than the default warning: nothing here has failed, and amber
    // is the attention colour. it is also what separates this from the
    // SectionFailure directly below the same section, which is amber and IS a
    // failure - one colour for both would make the two read as one kind of thing
    @ViewBuilder
    private var Disagreement: some View {
        if let reconcile = reconcile {
            Group {
                switch reconcile {
                case let .pull(chapter):
                    // branched rather than ternaried so each string stays a
                    // literal - a ternary with a String on either side erases
                    // inflection markup
                    if let only = links.first, links.count == 1 {
                        Banner(
                            "\(only.tracker.name) is at chapter \(chapter)",
                            // what the tap does, said before it is tapped: this
                            // one writes read state across every source
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
                case let .push(chapter):
                    // and this one writes to a public list
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

    // pull wins where both are true at once - one service ahead of the reader
    // and another behind. reading up is the safer write, and the laggard is
    // brought along by the push that the mark itself enqueues, so the second
    // direction resolves without a second banner
    private var reconcile: TrackerReconcile? {
        guard reconciles, let furthest = links.map(\.progress).max() else { return nil }

        if furthest > localProgress { return .pull(furthest) }

        // a queued row is excluded, not just a slack of one chapter. accepting a
        // pull enqueues every sibling that is behind, so for the seconds between
        // that write and the drain landing, a laggard reads as a disagreement
        // while the fix is already in the queue - and the banner would flip from
        // pull to push in front of the reader, offering the work it just did
        let stale = links.filter { $0.behind(localProgress) && !$0.queued && !syncing.contains($0.tracker) }
        if !stale.isEmpty { return .push(localProgress) }
        return nil
    }

    // named where one service is linked, collective where two are: an alert
    // title carrying two service names and a number stops being a sentence
    private var pushSubject: String {
        links.count == 1 ? (links.first?.tracker.name ?? "your trackers") : "your trackers"
    }

    // every service with something to say here: one that is connected, and one
    // this series is linked to. the union matters because the two can come apart
    // - a deliberate sign-out leaves the link behind, and a row driven by the
    // account list alone would take a linked service off the screen entirely,
    // with no badge and nothing to act on. ordered by the enum rather than by
    // either set, so the rows do not reshuffle when an account comes or goes
    private var services: [Tracker] {
        let linked = Set(links.map(\.tracker))
        return Tracker.allCases.filter { accounts.contains($0) || linked.contains($0) }
    }

    // a service that cannot sync until the reader does something: signed out
    // while still linked, or connected with nothing left to refresh
    private func unavailable(_ tracker: Tracker) -> Bool {
        !accounts.contains(tracker) || needingSignIn.contains(tracker)
    }

    // one row's worth, not a screen's worth. ContentUnavailableView sizes itself
    // for an empty *screen*, and nothing here is missing or broken - tracking is
    // simply a thing this reader has not set up, sitting between two sections
    // that are full. it still carries the action that resolves it
    private var Empty: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Text("Connect an account to keep your lists in step with what you read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // the link circle's recipe with the shape following the content -
            // same glass, same interactive, text instead of a glyph
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

    // the target follows what the row IS. linked, it is a summary standing for
    // everything behind it, so the whole row opens that. unlinked, it is a
    // statement with one thing to do about it - and a full-width target there
    // would open a search sheet off a stray tap on a service name, which is the
    // affordance lie in the other direction
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

    // what the setup flow found for this service, or nil for every row that is
    // linked, unreachable, or simply outside that flow. one guard here rather
    // than the same three conditions in the title, the subtitle and the trailing
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

    // beside the service tile rather than instead of it: the tile says who is
    // proposing this and the cover says what, and the reader needs both to judge
    // it. the placeholder holds the same footprint while the search runs, so the
    // row does not jump sideways when the artwork lands
    @ViewBuilder
    private func Cover(_ match: DetailsComposer.Tracking.Match) -> some View {
        switch match {
        case .searching:
            CoverFrame { EmptyView() }
                .shimmer()

        case let .found(candidate):
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

    // the brand tile, drawn untinted - a logo recoloured to match its
    // surroundings has stopped being a logo
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
                // a linked row already replaces the service name with the entry
                // it points at. a match is the same statement one step earlier -
                // this is what the row would become - so it reads the same way,
                // and the tile is what says which service is proposing it
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

    // the row's state as a pill beside the name, which is where DetailsSources
    // puts PRIMARY and FAILING - one slot, one pill, in precedence order. an
    // account that needs signing in gets none: the subtitle already says so in
    // the same amber, and two of those in one row is the badge soup the design
    // rules name outright
    @ViewBuilder
    private func State(_ tracker: Tracker, link: Link?) -> some View {
        // an account that has run out and a push that failed are the same thing
        // to this row - nothing is reaching the service - so they wear the same
        // pill and differ in the sentence beneath and the control beside
        if link != nil, unavailable(tracker) || link?.failing == true {
            Badge(text: "SYNC FAILED", tone: .warning, size: .compact)
        } else if let status = link?.status {
            Badge(text: status.label.uppercased(), tone: status.tone, size: .compact)
        }
    }

    // one consolidated line rather than three facts on three rows. a linked
    // entry reads "Reading · 42 of 120 · 8/10", and only the parts that exist
    // appear - an unscored entry does not print an empty score
    @ViewBuilder
    private func Subtitle(_ tracker: Tracker, link: Link?) -> some View {
        Group {
            if let link {
                if link.behind(localProgress) {
                    // stated rather than corrected: the app owns reading and the
                    // service owns the list, so a disagreement is shown and the
                    // reader decides. the catch-up lives behind the row
                    Text("\(localProgress) here · \(link.progress) on \(tracker.name)")
                } else if let synced = link.synced {
                    // the stamp ticks, so it comes off the same clock the
                    // Trouble line below uses - one Text either way, built from
                    // the string LiveRelative hands back rather than an HStack
                    LiveRelative(date: synced) { relative in
                        Text("\(link.summary) · synced \(relative)")
                            .contentTransition(.numericText())
                            .animation(.default, value: relative)
                    }
                } else {
                    Text(link.summary)
                }
            } else if unavailable(tracker) {
                // nothing linked and nothing to sync, so the condition has this
                // line to itself rather than a reason line under a summary
                Text("Sign in again to keep tracking")
            } else if let match = match(tracker, link: link) {
                switch match {
                case .searching:
                    // a bar where the answer will be, rather than the word
                    // "searching" - the row is about to say something and this
                    // is the shape of the thing it will say
                    Capsule()
                        .fill(.primary.opacity(Layout.skeletonOpacity))
                        .frame(width: Layout.skeletonWidth, height: Layout.skeletonHeight)
                        .shimmer()
                        .accessibilityLabel("Searching \(tracker.name)")

                case let .found(candidate):
                    Text(facts(for: candidate))

                case .unmatched:
                    // a fact about a search that ran, not an apology. the reader
                    // never asked for it, so it states the outcome and stops
                    Text("No exact match")
                }
            } else {
                Text("Not linked")
            }
        }
        .font(.caption2)
        .foregroundStyle(subtitleTint(tracker, link: link))
        .lineLimit(1)
    }

    // amber is for a service that has stopped syncing. being behind used to take
    // it too, which was one fact in three places once the banner arrived - badge,
    // amber line, banner - so the line keeps the numbers and gives up the colour.
    // the banner is the one that shouts, and it is also the only one that can be
    // acted on
    private func subtitleTint(_ tracker: Tracker, link: Link?) -> AnyShapeStyle {
        if unavailable(tracker) && link == nil {
            AnyShapeStyle(.warningText)
        } else {
            AnyShapeStyle(.muted)
        }
    }

    // the attempt date, not a first-seen date - one column cannot honestly claim
    // when a failure started. the same second line for both conditions: what is
    // wrong, and when we last got nowhere
    @ViewBuilder
    private func Trouble(_ tracker: Tracker, link: Link) -> some View {
        if let reason = reason(tracker, link: link) {
            Group {
                if link.attemptedDate > .distantPast {
                    // one Text, or the sentence stops wrapping
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

    // the account outranks the push: a dead account is WHY the push failed, so
    // saying "you're offline" under it would name the symptom over the cause
    private func reason(_ tracker: Tracker, link: Link) -> String? {
        if unavailable(tracker) { return "Sign in again to keep tracking." }
        return link.failureReason
    }

    // an indicator rather than a second target - the row is the target. unlinked
    // gets a filled brand circle because a bare glyph in a caption-height row is
    // the affordance nobody recognises; linked gets the chevron, which is what
    // "there is more in here" has always meant.
    //
    // one Image across all three states rather than three branches: the glyph
    // changes in the same slot, so it replaces rather than crossfades, and a
    // branch swap would give each state its own identity and defeat that. the
    // spinner is a symbol for the same reason - a ProgressView has no stroke to
    // draw out of
    @ViewBuilder
    private func Trailing(_ tracker: Tracker, link: Link?) -> some View {
        if unavailable(tracker) {
            // whatever the row is otherwise, the only useful thing to do about a
            // service that cannot sync is sign in - so linked and unlinked both
            // point at the same place rather than offering Link, which would
            // fail, or a chevron into a screen that cannot help
            Glyph(for: tracker, link: link)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .tappable(action: onConnect)
                .accessibilityLabel("Sign in to \(tracker.name) again")
        } else if let link, link.failing, !syncing.contains(tracker) {
            // the same shape, a different verb. this one really is "try that
            // again" - the queue kept every pending column, so a retry is the
            // walk being asked to run now rather than at its next wake
            Glyph(for: tracker, link: link)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .tappable { onRetry(link) }
                .accessibilityLabel("Retry syncing to \(tracker.name)")
        } else if case let .found(candidate)? = match(tracker, link: link), !syncing.contains(tracker) {
            // two circles where the row normally has one, in the same shape the
            // rest of the app uses for a lone control against the canvas. Link
            // commits what was found; the magnifying glass says it is not the
            // one and opens the search that would have opened anyway
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
            // the app's one shape for a lone circular control against the canvas,
            // same recipe as HomeScreen.Action and the chart's stepper. the glass
            // IS the affordance - a glyph with nothing behind it cannot say
            // "control" - and the foreground stays semantic, because glass vends
            // its own content colour and a pinned Palette step overrules it
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
            // a continuously spinning symbol is the thing Reduce Motion exists
            // for, and the subtitle beside it already says what is happening
            // gated on this row's own service, not on the modifier merely being
            // present: left unconditional it spins whatever glyph is in the slot,
            // so two linked rows sat rotating their chevrons forever
            .symbolEffect(
                .rotate,
                options: .repeat(.continuous),
                isActive: syncing.contains(tracker) && !reduceMotion
            )
            .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
            // the state arrives from an observation with no animation of its
            // own, so contentTransition has nothing to run inside without this
            .animation(.settle, value: syncing)
    }

    // the same recipe the single trailing control uses, factored out because a
    // matched row needs two of them. glass IS the affordance here, so the busy
    // state swaps the glyph rather than the surface - a control that loses its
    // background mid-tap reads as having been dismissed
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
        if case let .found(candidate)? = match(tracker, link: link) { return candidate.title }
        return tracker.name
    }

    // year and length, the two facts that separate a series from its own sequel
    // once the title has already matched. either may be missing, and with both
    // gone the service name is all there is left to say
    private func facts(for candidate: TrackerCandidate) -> String {
        var parts: [String] = []
        if let year = candidate.year { parts.append(String(year)) }
        if let total = candidate.totalChapters { parts.append("\(total) chapters") }
        return parts.isEmpty ? "Match found" : parts.joined(separator: " · ")
    }

    private func glyph(for tracker: Tracker, link: Link?) -> String {
        if syncing.contains(tracker) { return "progress.indicator" }
        // two conditions, two verbs, and they must not share a glyph: this one
        // is about the ACCOUNT, and a circular arrow beside it would promise
        // that tapping retries the sync - which would fail again for the same
        // reason it failed the first time
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

private extension DetailsTracking.Link {
    static func sample(
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

// every state the section can be in, stacked, so a design change is judged
// against all of them at once rather than one screenshot at a time
#Preview("States") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            TrackingPreview(accounts: [], caption: "No account connected")

            // the state this section spent its life rendering as nothing at all
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
                links: [.sample(), .sample(.myAnimeList, status: .completed, progress: 120, score: 90)],
                localProgress: 120,
                caption: "Both linked"
            )

            TrackingPreview(
                links: [.sample()],
                syncing: [.anilist],
                caption: "Syncing"
            )

            // the row exists because the LINK does, not because the account does.
            // driven by accounts alone this row was absent entirely - a series
            // still linked to a service, with nothing on screen saying so
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

            // the same condition with nothing linked yet: Link is gone, because
            // linking would fail, and the row points at signing in instead
            TrackingPreview(
                needingSignIn: [.anilist, .myAnimeList],
                caption: "Both need signing in, neither linked"
            )
        }
        .padding(16)
    }
    .background(.canvas)
}

// the two states that carry a colour, kept apart from the resting ones - both
// are warning-toned and it must stay obvious which is a fault and which is not
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

// a long remote title next to a long subtitle is where the row truncates first,
// and 320pt is the narrowest thing this has to survive
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

// every state the section moves through, steppable in order, because a static
// preview shows endpoints and says nothing about the swap between them. the
// order is the real lifecycle: nothing connected, connected, linked, a push, a
// disagreement, a failure, an account running out, and signed out with the link
// still there
#Preview("Live states") {
    @Previewable @State var step = 0

    let states: [(String, [Tracker], [DetailsTracking.Link], Set<Tracker>, Set<Tracker>)] = [
        ("No account connected", [], [], [], []),
        ("Connected, nothing linked", [.anilist, .myAnimeList], [], [], []),
        ("One linked", [.anilist, .myAnimeList], [.sample()], [], []),
        ("Pushing", [.anilist, .myAnimeList], [.sample()], [.anilist], []),
        ("Service is behind", [.anilist, .myAnimeList], [.sample(progress: 12)], [], []),
        ("Finished on the service", [.anilist, .myAnimeList], [.sample(status: .completed, progress: 122)], [], []),
        ("Sync failed - retry beside it", [.anilist, .myAnimeList], [.sample(failure: "You're offline.")], [], []),
        ("Token run out - sign in beside it", [.anilist, .myAnimeList], [.sample()], [], [.anilist]),
        ("Signed out, still linked", [.myAnimeList], [.sample()], [], [])
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

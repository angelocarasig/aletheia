    //
//  ReaderSeparatorView.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// the boundary between two chapters, rendered as a stack of slots. every slot
// is independently conditional and declares its own height in
// ReaderSeparatorModel.Metrics - keep the two in step, the layout trusts the
// numbers there rather than measuring this view
struct ReaderSeparatorView: View {
    let model: ReaderSeparatorModel
    var onRetry: () -> Void
    var onComplete: () -> Void = {}
    var onExplainGap: (ReaderSeparatorModel.Gap) -> Void = { _ in }

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    private enum Layout {
        static let ruleWidth: CGFloat = 64
        static let ruleHeight: CGFloat = 1
        static let ruleHeightContrast: CGFloat = 2
        static let gapTarget: CGFloat = 44
        static let dotSize: CGFloat = 5
        static let eventBadge: CGFloat = 18
        // a tile needs more area than a glyph to be recognisable, so it runs a
        // little larger than the caption beside it and takes a corner radius
        // rather than sitting as a hard square
        static let trackerIcon: CGFloat = 18
        static let trackerIconRadius: CGFloat = 4
        // narrower than the band so the block reads as an inset island rather
        // than a full-width table inside a centred layout
        static let trackerIsland: CGFloat = 240
    }

    // every reserved box is a constant per content-size category, so the view
    // has to ask the same question the layout did or the two disagree
    private var category: UIContentSizeCategory { .init(dynamicTypeSize) }

    private func slot(_ value: CGFloat) -> CGFloat {
        ReaderSeparatorModel.Metrics.scaled(value, category)
    }

    var body: some View {
        // two statements, not six announcements. what you finished and where it
        // was recorded read as one thing; what you are entering and everything
        // describing it read as another. the rule between them is the boundary
        VStack(spacing: ReaderSeparatorModel.Metrics.spacing) {
            if let terminal = model.terminal {
                VStack(spacing: ReaderSeparatorModel.Metrics.group) {
                    Terminal(terminal)

                    // absent going backward rather than hidden: nothing was
                    // pushed, so there is no state to report. the group keeps
                    // its declared height either way and centres what remains,
                    // so the rows leaving does not open a hole beneath the
                    // chapter - which is what the space is reserved for
                    if !model.trackers.isEmpty, model.direction == .forward {
                        Trackers
                    }
                }
                .frame(height: model.behind(for: category))

                Rule
            }

            VStack(spacing: ReaderSeparatorModel.Metrics.group) {
                Destination

                // describes the chapter being entered rather than the boundary,
                // so it sits under it instead of floating between the two halves
                // as a peer of them. the gap is not here - it belongs to the
                // crossing, and rides the rule
                if let continuity = model.continuity, !continuity.isEmpty {
                    Continuity(continuity)
                }
            }

            // reserved whether or not there is an action: the height must not
            // change when a destination resolves or fails
            Action
        }
        .padding(.vertical, ReaderSeparatorModel.Metrics.padding)
        .padding(.horizontal, dimensions.spacing.space24)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Slots

private extension ReaderSeparatorView {
    func Terminal(_ terminal: ReaderSeparatorModel.Terminal) -> some View {
        VStack(spacing: dimensions.spacing.space2) {
            Text(model.direction == .forward ? "Finished" : "Returning from")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: dimensions.spacing.space8) {
                Text("Chapter \(terminal.number.formatted())")
                    .font(.headline)

                EventBadge
            }
        }
        .frame(height: slot(ReaderSeparatorModel.Metrics.terminal))
    }

    // the write's own state, injected through the model. geometry only - the
    // badge is .secondary, so colour-based effects read as nothing here. the
    // ring spins while the event row is in flight; the check enters by drawing
    // itself along its stroke path (draw-on), the outgoing side draws off.
    // forward only: backward travel records nothing
    @ViewBuilder
    var EventBadge: some View {
        if model.direction == .forward, let event = model.event {
            Group {
                switch event {
                case .recording:
                    Image(systemName: "progress.indicator")
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                        .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

                case .recorded:
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: Layout.eventBadge, height: Layout.eventBadge)
            .animation(.settle, value: event)
            .accessibilityLabel(event == .recorded ? "Chapter recorded" : "Recording chapter")
        }
    }

    // v2's grammar, and the reason is alignment rather than count: laid out
    // horizontally, a tick after each name floats mid-line and repeats, so two
    // services read as clutter. stacked with the status pushed to a trailing
    // column, the glyphs line up and the block scans in one pass - which is
    // exactly why the same content worked in v2's transition card.
    //
    // the island is width-limited and centred rather than spanning the band, so
    // a left-aligned block can live inside a centred one without fighting it
    var Trackers: some View {
        VStack(spacing: ReaderSeparatorModel.Metrics.trackerGap) {
            ForEach(model.trackers) { tracker in
                TrackerRow(tracker)
            }
        }
        .frame(maxWidth: Layout.trackerIsland)
        .animation(.settle, value: model.trackers)
    }

    func TrackerRow(_ tracker: ReaderSeparatorModel.Tracker) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            // the service's own tile, colour intact. this is the one place brand
            // palette is allowed into the band: a logo recoloured to .secondary
            // stops being a logo and reads as two unexplained letters
            if let icon = tracker.icon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Layout.trackerIcon, height: Layout.trackerIcon)
                    .clipShape(.rect(cornerRadius: Layout.trackerIconRadius))
            }

            Text(tracker.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: dimensions.spacing.space12)

            HStack(spacing: dimensions.spacing.space4) {
                TrackerState(tracker.state)

                // the word does what the glyph cannot: say which of the four
                // states this is without the reader learning a vocabulary
                Text(tracker.state.label)
                    .font(.caption2)
            }
            .foregroundStyle(tracker.state.tint)
        }
        .frame(height: slot(ReaderSeparatorModel.Metrics.trackerRow))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tracker.name)
        .accessibilityValue(tracker.state.label)
    }

    @ViewBuilder
    func TrackerState(_ state: ReaderSeparatorModel.Tracker.State) -> some View {
        Group {
            switch state {
            case .loading:
                Image(systemName: "progress.indicator")
                    // continuous rather than the default stepped rotation, which
                    // reads as stuttering on a push that takes a moment. off
                    // under reduce motion - the word beside it already says
                    // Syncing, so nothing is lost by holding still
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .tracked:
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            // never a tick - the push declined to claim this chapter, and a
            // check would say it landed
            case .skipped:
                Image(systemName: "minus.circle")
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            // stated, not actionable: the failure persists to Details, where
            // there is somewhere to act on it. unfilled like its three
            // siblings: draw-on traces a stroke path, and a solid glyph has
            // none, so the fill variant crossfaded where the others drew
            case .errored:
                Image(systemName: "exclamationmark.triangle")
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .font(.caption2)
    }

    // a footnote on the chapter above it now, so it drops a step in weight -
    // which source is serving the next chapter matters only if you notice the
    // art change, and never more than the chapter number it belongs to
    func Continuity(_ continuity: ReaderSeparatorModel.Continuity) -> some View {
        HStack(spacing: dimensions.spacing.space4) {
            Image(systemName: "arrow.triangle.swap")
                .font(.caption2)

            Text(continuity.summary)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.tertiary)
        .frame(height: slot(ReaderSeparatorModel.Metrics.continuity))
    }


    // the rule is the crossing, and a gap is what makes that crossing
    // non-contiguous - so the range goes in the break rather than becoming a row
    // underneath the chapter it does not describe. nothing failed here: 45-49
    // exist nowhere you have a source for, which is a fact about the jump and
    // not an error, so it wears the rule's own weight instead of an alarm colour
    // tertiary on black measures around 2.5:1 - under the 3:1 floor for
    // non-text, and a 1pt hairline with a 5pt dot is below the threshold of a
    // dimmed OLED besides. decorative, so it is a should-fix at default
    // settings and a must once the reader has asked for more contrast
    var ruleStyle: HierarchicalShapeStyle {
        contrast == .increased ? .secondary : .tertiary
    }

    var ruleHeight: CGFloat {
        contrast == .increased ? Layout.ruleHeightContrast : Layout.ruleHeight
    }

    var Rule: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Capsule()
                .fill(ruleStyle)
                .frame(width: Layout.ruleWidth, height: ruleHeight)

            if let gap = model.gap {
                // the only tappable thing on an ordinary boundary, and only
                // this - readers reached for it unprompted, one of them reading
                // the non-response as her phone misbehaving. the band itself
                // stays inert: a full-width target crossed on every boundary
                // would fire by accident mid-scroll.
                //
                // the tap explains rather than navigates. the reader who wants
                // to know is mid-chapter and does not want to be taken anywhere
                Text(gap.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    // the visible text is caption2 inside a 24pt rule, so the
                    // target is grown around it rather than by it - the frame
                    // overflows the rule it sits in, which nothing clips
                    .padding(.horizontal, dimensions.spacing.space8)
                    .frame(minHeight: Layout.gapTarget)
                    .contentShape(.rect)
                    .tappable { onExplainGap(gap) }
                    .accessibilityLabel(gap.spoken)
                    .accessibilityHint("Explains why these chapters are not here")
            } else {
                Circle()
                    .fill(ruleStyle)
                    .frame(width: Layout.dotSize, height: Layout.dotSize)
            }

            Capsule()
                .fill(ruleStyle)
                .frame(width: Layout.ruleWidth, height: ruleHeight)
        }
        .frame(height: ReaderSeparatorModel.Metrics.rule)
    }

    @ViewBuilder
    var Destination: some View {
        switch model.destination {
        case let .chapter(number, title):
            VStack(spacing: dimensions.spacing.space2) {
                Text(model.direction == .forward ? "Up next" : "Back to")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Chapter \(number.formatted())")
                    .font(.title3)
                    .fontWeight(.semibold)

                if !title.isEmpty, title != "Chapter \(number.formatted())" {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: slot(ReaderSeparatorModel.Metrics.destination))

        case let .loading(number):
            VStack(spacing: dimensions.spacing.space8) {
                ProgressView()

                Text(number.map { "Loading Chapter \($0.formatted())" } ?? "Loading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: slot(ReaderSeparatorModel.Metrics.destination))

        case let .failed(error):
            VStack(spacing: dimensions.spacing.space2) {
                Text(error.errorDescription ?? "Couldn't Load")
                    .font(.headline)

                Text(error.failureReason ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(height: slot(ReaderSeparatorModel.Metrics.destination))

        case .caughtUp:
            VStack(spacing: dimensions.spacing.space2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.successText)

                Text("You're all caught up")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(height: slot(ReaderSeparatorModel.Metrics.destination))

        case .startOfSeries:
            VStack(spacing: dimensions.spacing.space2) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Start of series")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(height: slot(ReaderSeparatorModel.Metrics.destination))
        }
    }

    @ViewBuilder
    var Action: some View {
        Group {
            switch model.action {
            case .retry:
                Button("Try Again", action: onRetry)
                    .buttonStyle(.glassProminent)

            // an offer, never a write that happened on its own - a source can
            // call a work complete while holding half its chapters. the label
            // names the outcome, and declining costs one scroll.
            //
            // no fill and no shape: every other slot in this band is bare type,
            // so a capsule would be the only object in it and would outweigh the
            // sentence it is answering. retry keeps its prominent style because
            // it is blocking - nothing continues until it is answered - where
            // this one is optional and scrolling past is a legitimate answer.
            // brand carries the affordance, the glyph keeps it from reading as
            // one more caption
            case .complete:
                Label("Mark as Completed", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.brand)
                    .contentShape(.rect)
                    .tappable(action: onComplete)

            case nil:
                EmptyView()
            }
        }
        .frame(height: slot(ReaderSeparatorModel.Metrics.action))
    }
}

// MARK: - Copy

private extension ReaderSeparatorModel.Continuity {
    var summary: String {
        [source, scanlator, language]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private extension ReaderSeparatorModel.Tracker.State {
    var label: String {
        switch self {
        case .loading: "Syncing"
        case .tracked: "Synced"
        case .skipped: "Skipped"
        case .errored: "Failed"
        }
    }

    // the glyph and the word carry one colour between them, so a state is never
    // told twice in two different weights
    var tint: Color {
        switch self {
        case .loading, .tracked: Palette.muted
        case .skipped: Palette.muted
        case .errored: Palette.warningText
        }
    }
}

private extension ReaderSeparatorModel.Gap {
    // "skipping" put the app in charge of a decision it never made - readers
    // consistently heard it as "the app chose to skip these" or "did I skip
    // these", and one assumed the chapters had been taken from her. it is
    // absence, not a decision, so the state word carries it and no verb does.
    // numbers first, because a long range already crowds the rule and the digits
    // are what the eye is looking for
    var summary: String {
        count == 1
            ? "\(from.formatted()) unavailable"
            : "\(from.formatted())–\(to.formatted()) unavailable"
    }

    // VoiceOver has none of that flanking context, so it gets the sentence
    var spoken: String {
        count == 1
            ? "Chapter \(from.formatted()) unavailable"
            : "Chapters \(from.formatted()) to \(to.formatted()) unavailable"
    }
}

// MARK: - Previews

// the separator has no orientation input - it renders identically in every
// reading mode. its real axes are travel direction, destination state, and the
// per-chapter rows, so each preview below stacks one axis rather than giving
// every state a canvas of its own. Specimen labels and rules the specimens,
// because two separators in a column are otherwise indistinguishable

private extension ReaderSeparatorModel {
    static func sample(
        _ destination: Destination = .chapter(number: 45, title: "Aftermath"),
        direction: ReadingDirection = .forward,
        boundary: ReaderBoundary = .after(1),
        terminal: Terminal? = .init(number: 44, title: "The Gathering Storm"),
        continuity: Continuity? = nil,
        gap: Gap? = nil,
        event: EventStatus? = nil,
        completable: Bool = false,
        trackers: [Tracker] = []
    ) -> Self {
        .init(
            boundary: boundary,
            direction: direction,
            terminal: terminal,
            continuity: continuity,
            gap: gap,
            destination: destination,
            event: event,
            completable: completable,
            trackers: trackers
        )
    }

    static let linked: [Tracker] = [
        .init(id: "anilist", name: "AniList", icon: "AniList", state: .tracked),
        .init(id: "mal", name: "MyAnimeList", icon: "MyAnimeList", state: .tracked)
    ]
}

private struct Specimen: View {
    let title: String
    let model: ReaderSeparatorModel
    var onComplete: () -> Void = {}
    var onExplainGap: (ReaderSeparatorModel.Gap) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            ReaderSeparatorView(model: model, onRetry: {}, onComplete: onComplete)

            // the declared height is the contract this component lives by, so
            // the specimen states it rather than leaving it to be eyeballed
            Text(verbatim: "\(Int(model.height))pt")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)

            Divider()
        }
    }
}

private struct Sheet<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                content()
            }
            .padding(.vertical, 24)
        }
        .background(.canvas)
    }
}

#Preview("Travel") {
    Sheet {
        Specimen(title: "Forward", model: .sample())
        Specimen(
            title: "Backward",
            model: .sample(
                .chapter(number: 44, title: "The Gathering Storm"),
                direction: .backward,
                terminal: .init(number: 45, title: "Aftermath")
            )
        )
    }
}

#Preview("Destination") {
    Sheet {
        Specimen(title: "Up next", model: .sample())
        Specimen(title: "Loading", model: .sample(.loading(number: 45)))
        Specimen(title: "Failed — retryable", model: .sample(.failed(.offline(2))))
        Specimen(title: "Caught up", model: .sample(.caughtUp))
        Specimen(
            title: "Start of series",
            model: .sample(.startOfSeries, direction: .backward, boundary: .start, terminal: nil)
        )
    }
}

#Preview("Chapter event") {
    Sheet {
        Specimen(title: "Recording", model: .sample(event: .recording))
        Specimen(title: "Recorded", model: .sample(event: .recorded))
    }
}

// the badge draws itself on rather than crossfading, which only reads in motion
#Preview("Chapter event — live") {
    @Previewable @State var event: ReaderSeparatorModel.EventStatus?

    Sheet {
        Specimen(title: "Recording → recorded", model: .sample(event: event))
    }
    .task {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            event = .recording
            try? await Task.sleep(for: .seconds(1.5))
            event = .recorded
            try? await Task.sleep(for: .seconds(2))
            event = nil
        }
    }
}

// the gap rides the rule rather than taking a row, so these all cost the same
// height as a boundary with no gap at all. the run of widths is the point: the
// break has to stay legible from one chapter to a four-figure range
#Preview("Gap") {
    Sheet {
        Specimen(title: "No gap", model: .sample())
        Specimen(
            title: "One chapter",
            model: .sample(.chapter(number: 46, title: "Aftermath"), gap: .init(from: 45, to: 45, count: 1))
        )
        Specimen(
            title: "Short range",
            model: .sample(.chapter(number: 50, title: "Return"), gap: .init(from: 45, to: 49, count: 5))
        )
        Specimen(
            title: "Long range, four figures",
            model: .sample(.chapter(number: 1240, title: ""), gap: .init(from: 1102, to: 1239, count: 138))
        )
        // the two things that annotate the crossing and the destination, at once
        Specimen(
            title: "With continuity",
            model: .sample(
                .chapter(number: 50, title: "Return"),
                continuity: .init(source: "MangaDex", scanlator: "Asura Scans", language: "EN"),
                gap: .init(from: 45, to: 49, count: 5)
            )
        )
        // a gap immediately before the end of what exists - the two facts are
        // unrelated and both survive
        Specimen(
            title: "Gap into the ending",
            model: .sample(.caughtUp, gap: .init(from: 45, to: 49, count: 5), completable: true)
        )
    }
}

#Preview("Trackers") {
    Sheet {
        Specimen(
            title: "Every state",
            model: .sample(
                event: .recorded,
                trackers: [
                    .init(id: "a", name: "AniList", icon: "AniList", state: .loading),
                    .init(id: "b", name: "MyAnimeList", icon: "MyAnimeList", state: .tracked),
                    // no mark bundled - the row falls back to the name alone
                    .init(id: "c", name: "Kitsu", state: .skipped),
                    .init(id: "d", name: "MangaUpdates", state: .errored)
                ]
            )
        )
        // the rows keep their height and drop their glyph: presence is linkage,
        // not travel, and backward pushes nothing
        Specimen(
            title: "Backward — no push",
            model: .sample(
                .chapter(number: 44, title: "The Gathering Storm"),
                direction: .backward,
                terminal: .init(number: 45, title: "Aftermath"),
                trackers: ReaderSeparatorModel.linked
            )
        )
    }
}

#Preview("Ending") {
    Sheet {
        Specimen(title: "Offered", model: .sample(.caughtUp, completable: true))
        // same sentence, no offer - the one thing it asked has been answered
        Specimen(title: "Already completed", model: .sample(.caughtUp))
        // what the offer is meant to sit inside once trackers land
        Specimen(
            title: "With trackers",
            model: .sample(
                .caughtUp,
                event: .recorded,
                completable: true,
                trackers: ReaderSeparatorModel.linked
            )
        )
    }
}

// tapping the offer empties the action row without moving anything below it,
// which is the whole reason the row is reserved
#Preview("Ending — live") {
    @Previewable @State var completable = true

    Sheet {
        Specimen(
            title: "Tap to mark",
            model: .sample(.caughtUp, completable: completable, trackers: ReaderSeparatorModel.linked),
            onComplete: { withAnimation(.settle) { completable = false } }
        )
    }
}

// every slot at once - the tallest the band ever gets, and the layout the
// declared height arithmetic has to match
#Preview("Full stack") {
    Sheet {
        Specimen(
            title: "All slots",
            model: .sample(
                .chapter(number: 50, title: "Return"),
                continuity: .init(source: "MangaDex", scanlator: "Asura Scans", language: "EN"),
                gap: .init(from: 45, to: 49, count: 5),
                event: .recorded,
                trackers: ReaderSeparatorModel.linked
            )
        )
    }
}

// the reader pins a dark scheme regardless of system appearance, so this is the
// appearance the component actually ships in
#Preview("Dark") {
    Sheet {
        Specimen(title: "Up next", model: .sample(event: .recorded, trackers: ReaderSeparatorModel.linked))
        Specimen(
            title: "Ending, offered",
            model: .sample(.caughtUp, completable: true, trackers: ReaderSeparatorModel.linked)
        )
        Specimen(title: "Failed", model: .sample(.failed(.offline(2))))
    }
    .environment(\.colorScheme, .dark)
}

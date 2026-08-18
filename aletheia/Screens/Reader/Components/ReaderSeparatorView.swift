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
    // per service, because one can be failing while the other is fine. distinct
    // from onRetry above, which retries the CHAPTER this separator could not load
    var onRetryTracker: (String) -> Void = { _ in }
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

                    // absent until the boundary has been crossed rather than
                    // hidden: a chapter nobody finished pushed nothing, so there
                    // is no state to report. it is the crossing that decides,
                    // not the direction of travel - coming back to a boundary
                    // you finished earlier finds its rows where you left them.
                    // the group keeps its declared height either way and centres
                    // what remains, so the rows leaving does not open a hole
                    // beneath the chapter - which is what the space is reserved for
                    if !model.trackers.isEmpty, model.crossed {
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

extension ReaderSeparatorView {
    fileprivate func Terminal(_ terminal: ReaderSeparatorModel.Terminal) -> some View {
        VStack(spacing: dimensions.spacing.space2) {
            // the slot holds the boundary's own chapter in both directions - the
            // one below the band - so going back up you are entering it, not
            // leaving it. the words used to say the opposite of the numbers they
            // sat beside
            Text(model.direction == .forward ? "Finished" : "Back to")
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
    // survives turning round: the write belongs to the chapter rather than to
    // the trip, so coming back to a boundary finds the tick it earned
    @ViewBuilder
    fileprivate var EventBadge: some View {
        if model.crossed, let event = model.event {
            Group {
                switch event {
                case .recording:
                    Image(systemName: "progress.indicator")
                        .symbolEffect(
                            .rotate, options: .repeat(.continuous), isActive: !reduceMotion
                        )
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
    fileprivate var Trackers: some View {
        VStack(spacing: ReaderSeparatorModel.Metrics.trackerGap) {
            ForEach(model.trackers) { tracker in
                TrackerRow(tracker)
            }
        }
        .frame(maxWidth: Layout.trackerIsland)
        .animation(.settle, value: model.trackers)
    }

    // only the state that can be changed by a tap becomes a control. wrapping
    // every row in a Button would give four of five states a press response that
    // does nothing, which is the affordance lie in its purest form
    @ViewBuilder
    fileprivate func TrackerRow(_ tracker: ReaderSeparatorModel.Tracker) -> some View {
        if tracker.state.isRetryable {
            TrackerContent(tracker)
                .tappable { onRetryTracker(tracker.id) }
        } else {
            TrackerContent(tracker)
        }
    }

    fileprivate func TrackerContent(_ tracker: ReaderSeparatorModel.Tracker) -> some View {
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

                // the word does what the glyph cannot: say which state this is
                // without the reader learning a vocabulary - and when something
                // failed it says WHY, in the slot the generic word had
                Text(tracker.state.label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(tracker.state.tint)
        }
        .frame(height: slot(ReaderSeparatorModel.Metrics.trackerRow))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tracker.name)
        .accessibilityValue(tracker.state.label)
        .accessibilityHint(tracker.state.isRetryable ? "Try syncing again" : "")
    }

    @ViewBuilder
    fileprivate func TrackerState(_ state: ReaderSeparatorModel.Tracker.State) -> some View {
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

            // unfilled like its siblings: draw-on traces a stroke path, and a
            // solid glyph has none, so the fill variant crossfaded where the
            // others drew. this one IS actionable - the row retries it
            case .errored:
                Image(systemName: "arrow.clockwise")
                    .fontWeight(.semibold)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            // the account, not the push - and deliberately not an alarm glyph.
            // nothing is broken here: a connection ran out, which on one of the
            // two services is a yearly certainty. the dashed outline reads as
            // absent rather than as faulty, which is what an exclamation mark
            // beside a failure glyph two rows up would have said
            case .signedOut:
                Image(systemName: "person.crop.circle.dashed")
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .font(.caption2)
    }

    // a footnote on the chapter above it now, so it drops a step in weight -
    // which source is serving the next chapter matters only if you notice the
    // art change, and never more than the chapter number it belongs to
    fileprivate func Continuity(_ continuity: ReaderSeparatorModel.Continuity) -> some View {
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
    fileprivate var ruleStyle: HierarchicalShapeStyle {
        contrast == .increased ? .secondary : .tertiary
    }

    fileprivate var ruleHeight: CGFloat {
        contrast == .increased ? Layout.ruleHeightContrast : Layout.ruleHeight
    }

    fileprivate var Rule: some View {
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
    fileprivate var Destination: some View {
        switch model.destination {
        case .chapter(let number, let title):
            VStack(spacing: dimensions.spacing.space2) {
                Text(model.direction == .forward ? "Up next" : "Coming from")
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

        case .loading(let number):
            VStack(spacing: dimensions.spacing.space8) {
                ProgressView()

                Text(number.map { "Loading Chapter \($0.formatted())" } ?? "Loading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: slot(ReaderSeparatorModel.Metrics.destination))

        case .failed(let error):
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
    fileprivate var Action: some View {
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

extension ReaderSeparatorModel.Continuity {
    fileprivate var summary: String {
        [source, scanlator, language]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

extension ReaderSeparatorModel.Tracker.State {
    fileprivate var label: String {
        switch self {
        case .loading: "Syncing"
        case .tracked: "Synced"
        case .skipped: "Skipped"
        // the reason IS the word. "Failed" told the reader the one thing they
        // could already see from the glyph
        case .errored(let reason): reason
        // a statement, not an instruction: this row cannot be tapped and the
        // screen it would send you to is not reachable from inside the reader.
        // "Sign in" was a button's word on something that is not a button
        case .signedOut: "Signed out"
        }
    }

    // the glyph and the word carry one colour between them, so a state is never
    // told twice in two different weights
    fileprivate var tint: Color {
        switch self {
        case .loading, .tracked: Palette.muted
        case .skipped: Palette.muted
        case .errored, .signedOut: Palette.warningText
        }
    }

    // only one of the two amber states can be acted on from here. signing in
    // needs a screen this one cannot reach, so it states itself and stops
    fileprivate var isRetryable: Bool {
        if case .errored = self { true } else { false }
    }
}

extension ReaderSeparatorModel.Gap {
    // "skipping" put the app in charge of a decision it never made - readers
    // consistently heard it as "the app chose to skip these" or "did I skip
    // these", and one assumed the chapters had been taken from her. it is
    // absence, not a decision, so the state word carries it and no verb does.
    // numbers first, because a long range already crowds the rule and the digits
    // are what the eye is looking for
    fileprivate var summary: String {
        count == 1
            ? "\(from.formatted()) unavailable"
            : "\(from.formatted())-\(to.formatted()) unavailable"
    }

    // VoiceOver has none of that flanking context, so it gets the sentence
    fileprivate var spoken: String {
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

extension ReaderSeparatorModel {
    fileprivate static func sample(
        _ destination: Destination = .chapter(number: 45, title: "Aftermath"),
        direction: ReadingDirection = .forward,
        boundary: ReaderBoundary = .after(1),
        terminal: Terminal? = .init(number: 44, title: "The Gathering Storm"),
        continuity: Continuity? = nil,
        gap: Gap? = nil,
        event: EventStatus? = nil,
        // a specimen showing indicators is showing a boundary that was crossed,
        // so this defaults to what every such canvas needs rather than being
        // restated on each one
        crossed: Bool = true,
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
            crossed: crossed,
            completable: completable,
            trackers: trackers
        )
    }

    fileprivate static let linked: [Tracker] = [
        .init(id: "anilist", name: "AniList", icon: "AniList", state: .tracked),
        .init(id: "mal", name: "MyAnimeList", icon: "MyAnimeList", state: .tracked),
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
        Specimen(title: "Failed - retryable", model: .sample(.failed(.offline(2))))
        Specimen(title: "Caught up", model: .sample(.caughtUp))
        Specimen(
            title: "Start of series",
            model: .sample(.startOfSeries, direction: .backward, boundary: .start, terminal: nil)
        )
    }
}
// the badge draws itself on rather than crossfading, which only reads in motion
#Preview("Chapter event") {
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
// the lifecycle, which is the part a static preview cannot show: crossing a
// boundary starts both services, they settle independently, and the state then
// FREEZES - the queue clears for the series, so without the freeze finishing the
// next chapter would send this boundary back to spinning
#Preview("Trackers") {
    @Previewable @State var step = 0
    @Previewable @State var backward = false

    let phases:
        [(String, ReaderSeparatorModel.EventStatus?, [ReaderSeparatorModel.Tracker.State])] = [
            ("Not crossed yet", nil, [.skipped, .skipped]),
            ("Just crossed - event recording, both owed", .recording, [.loading, .loading]),
            ("Event written, pushes still owed", .recorded, [.loading, .loading]),
            ("AniList landed", .recorded, [.tracked, .loading]),
            ("Both landed", .recorded, [.tracked, .tracked]),
            ("MyAnimeList came back failing", .recorded, [.tracked, .errored("You're offline")]),
            ("Signed out - needs the reader", .recorded, [.tracked, .signedOut]),
            ("Entry already finished - nothing to push", .recorded, [.tracked, .skipped]),
        ]

    let phase = phases[step % phases.count]

    Sheet {
        VStack(spacing: 12) {
            Text(phase.0)
                .font(.caption)
                .fontWeight(.semibold)
                .contentTransition(.opacity)

            Button("Next phase") { withAnimation(.settle) { step += 1 } }
                .buttonStyle(.glassProminent)

            // presence is the crossing, not travel: turning this on must change
            // nothing at all about the indicators - what was recorded is still
            // recorded when you come back to it
            Toggle("Reading backward", isOn: $backward)
                .font(.caption)
        }
        .padding(.horizontal, 16)

        Specimen(
            title: "Step \(step % phases.count + 1) of \(phases.count)",
            // the numbers do NOT swap with direction: 44's pages are above the
            // band and 45's are below it whichever way the reader is travelling,
            // so only the words change. the previous version swapped them and
            // drew a band the engine cannot produce, which is how the inverted
            // copy passed review
            model: .sample(
                .chapter(number: 45, title: "Aftermath"),
                direction: backward ? .backward : .forward,
                terminal: .init(number: 44, title: "The Gathering Storm"),
                event: phase.1,
                // the first phase is a boundary nobody has finished, which is
                // the one state that draws no indicators at all
                crossed: step % phases.count != 0,
                trackers: [
                    .init(id: "anilist", name: "AniList", icon: "AniList", state: phase.2[0]),
                    .init(
                        id: "myanimelist", name: "MyAnimeList", icon: "MyAnimeList",
                        state: phase.2[1]),
                ]
            )
        )
    }
}
// tapping the offer empties the action row without moving anything below it,
// which is the whole reason the row is reserved
#Preview("Ending") {
    @Previewable @State var completable = true

    Sheet {
        Specimen(
            title: "Tap to mark",
            model: .sample(
                .caughtUp, completable: completable, trackers: ReaderSeparatorModel.linked),
            onComplete: { withAnimation(.settle) { completable = false } }
        )
    }
}
// the reader pins a dark scheme regardless of system appearance, so this is the
// appearance the component actually ships in
// every slot that can change content WITHOUT changing height, driven one at a
// time. the number under each specimen is the declared height: if it moves while
// stepping through these, a slot is sizing itself off its content and the band
// will jump mid-read
#Preview("Full stack") {
    @Previewable @State var event = false
    @Previewable @State var completable = false
    @Previewable @State var trackers = false
    @Previewable @State var gap = false

    return Sheet {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Reading event", isOn: $event)
            Toggle("Completion offer", isOn: $completable)
            Toggle("Tracker rows", isOn: $trackers)
            Toggle("Missing chapters", isOn: $gap)
        }
        .font(.caption)
        .padding(.horizontal, 16)

        Specimen(
            title: "Height must not move",
            model: .sample(
                .caughtUp,
                continuity: .init(source: "MangaDex", scanlator: "Tempest", language: nil),
                gap: gap ? .init(from: 45, to: 49, count: 5, sources: ["MangaDex"]) : nil,
                event: event ? .recorded : nil,
                completable: completable,
                trackers: trackers ? ReaderSeparatorModel.linked : []
            )
        )
    }
}

#Preview("Dark") {
    Sheet {
        Specimen(
            title: "Up next",
            model: .sample(event: .recorded, trackers: ReaderSeparatorModel.linked))
        Specimen(
            title: "Ending, offered",
            model: .sample(.caughtUp, completable: true, trackers: ReaderSeparatorModel.linked)
        )
        Specimen(title: "Failed", model: .sample(.failed(.offline(2))))
    }
    .environment(\.colorScheme, .dark)
}

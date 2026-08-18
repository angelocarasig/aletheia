//
//  ReaderSeparatorView.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// every slot declares its own height in ReaderSeparatorModel.Metrics - keep the
// two in step, the layout trusts those numbers rather than measuring this view
struct ReaderSeparatorView: View {
    let model: ReaderSeparatorModel
    var onRetry: () -> Void
    // per service - distinct from onRetry, which retries the whole chapter
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
        static let trackerIcon: CGFloat = 18
        static let trackerIconRadius: CGFloat = 4
        static let trackerIsland: CGFloat = 240
    }

    // reserved-box heights are constants per content-size category, so this
    // must resolve the same category the layout used or the two disagree
    private var category: UIContentSizeCategory { .init(dynamicTypeSize) }

    private func slot(_ value: CGFloat) -> CGFloat {
        ReaderSeparatorModel.Metrics.scaled(value, category)
    }

    var body: some View {
        VStack(spacing: ReaderSeparatorModel.Metrics.spacing) {
            if let terminal = model.terminal {
                VStack(spacing: ReaderSeparatorModel.Metrics.group) {
                    Terminal(terminal)

                    // crossed gates trackers, not direction - a boundary finished
                    // earlier still shows its rows on return
                    if !model.trackers.isEmpty, model.crossed {
                        Trackers
                    }
                }
                .frame(height: model.behind(for: category))

                Rule
            }

            VStack(spacing: ReaderSeparatorModel.Metrics.group) {
                Destination

                if let continuity = model.continuity, !continuity.isEmpty {
                    Continuity(continuity)
                }
            }

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

    // geometry only - colour-based state belongs to TrackerState below, not this badge
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

    fileprivate var Trackers: some View {
        VStack(spacing: ReaderSeparatorModel.Metrics.trackerGap) {
            ForEach(model.trackers) { tracker in
                TrackerRow(tracker)
            }
        }
        .frame(maxWidth: Layout.trackerIsland)
        .animation(.settle, value: model.trackers)
    }

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
            // brand colour intact - the only place in this band a logo isn't recoloured to .secondary
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

            // unfilled, not the filled variant - draw-on needs a stroke path, which a solid glyph lacks
            case .errored:
                Image(systemName: "arrow.clockwise")
                    .fontWeight(.semibold)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .signedOut:
                Image(systemName: "person.crop.circle.dashed")
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .font(.caption2)
    }

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

    // tertiary-on-black measures ~2.5:1, under the 3:1 floor for non-text -
    // bumped to secondary once contrast is increased
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
                // added after user testing - readers tapped the gap unprompted
                // and read no response as their phone misbehaving
                Text(gap.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    // target grown around the text via frame, not by it - this
                    // frame overflows the rule it sits in and nothing clips it
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

            // an offer, not automatic - a source can report complete while still missing chapters
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
        case .errored(let reason): reason
        // statement, not instruction - this row can't be tapped and the sign-in
        // screen isn't reachable from here
        case .signedOut: "Signed out"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .loading, .tracked: Palette.muted
        case .skipped: Palette.muted
        case .errored, .signedOut: Palette.warningText
        }
    }

    fileprivate var isRetryable: Bool {
        if case .errored = self { true } else { false }
    }
}

extension ReaderSeparatorModel.Gap {
    // not "skipped" - user testing found readers heard that as the app choosing
    // to omit chapters, or worse, chapters taken from them
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

extension ReaderSeparatorModel {
    fileprivate static func sample(
        _ destination: Destination = .chapter(number: 45, title: "Aftermath"),
        direction: ReadingDirection = .forward,
        boundary: ReaderBoundary = .after(1),
        terminal: Terminal? = .init(number: 44, title: "The Gathering Storm"),
        continuity: Continuity? = nil,
        gap: Gap? = nil,
        event: EventStatus? = nil,
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
// state freezes once settled - without that, the next chapter's queue clearing
// would send this boundary back to spinning
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

            Toggle("Reading backward", isOn: $backward)
                .font(.caption)
        }
        .padding(.horizontal, 16)

        Specimen(
            title: "Step \(step % phases.count + 1) of \(phases.count)",
            // numbers do not swap with direction - a past version did, drawing a
            // band the engine cannot produce, and that's how the inverted copy passed review
            model: .sample(
                .chapter(number: 45, title: "Aftermath"),
                direction: backward ? .backward : .forward,
                terminal: .init(number: 44, title: "The Gathering Storm"),
                event: phase.1,
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
// height must not move as these toggle - if it does, a slot is sizing off
// content and the band will jump mid-read
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

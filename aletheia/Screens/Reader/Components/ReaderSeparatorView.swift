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

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let ruleWidth: CGFloat = 64
        static let ruleHeight: CGFloat = 1
        static let dotSize: CGFloat = 5
        static let eventBadge: CGFloat = 18
    }

    var body: some View {
        VStack(spacing: ReaderSeparatorModel.Metrics.spacing) {
            if let terminal = model.terminal {
                Terminal(terminal)
                Rule
            }

            if let continuity = model.continuity, !continuity.isEmpty {
                Continuity(continuity)
            }

            if let gap = model.gap {
                Gap(gap)
            }

            // the slot tracker rows will take, once trackers exist

            Destination

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
        .frame(height: ReaderSeparatorModel.Metrics.terminal)
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
                        .symbolEffect(.rotate, options: .repeat(.continuous))
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

    func Continuity(_ continuity: ReaderSeparatorModel.Continuity) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.caption)

            Text(continuity.summary)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(height: ReaderSeparatorModel.Metrics.continuity)
    }

    func Gap(_ gap: ReaderSeparatorModel.Gap) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)

            Text(gap.summary)
                .font(.caption)
                .lineLimit(2)
        }
        .foregroundStyle(Palette.warningText)
        .frame(height: ReaderSeparatorModel.Metrics.gap)
    }

    var Rule: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Capsule()
                .fill(.tertiary)
                .frame(width: Layout.ruleWidth, height: Layout.ruleHeight)

            Circle()
                .fill(.tertiary)
                .frame(width: Layout.dotSize, height: Layout.dotSize)

            Capsule()
                .fill(.tertiary)
                .frame(width: Layout.ruleWidth, height: Layout.ruleHeight)
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
            .frame(height: ReaderSeparatorModel.Metrics.destination)

        case let .loading(number):
            VStack(spacing: dimensions.spacing.space8) {
                ProgressView()

                Text(number.map { "Loading Chapter \($0.formatted())" } ?? "Loading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: ReaderSeparatorModel.Metrics.destination)

        case let .failed(error):
            VStack(spacing: dimensions.spacing.space2) {
                Text(error.errorDescription ?? "Couldn't Load")
                    .font(.headline)

                Text(error.failureReason ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(height: ReaderSeparatorModel.Metrics.destination)

        case .caughtUp:
            VStack(spacing: dimensions.spacing.space2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.successText)

                Text("You're all caught up")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(height: ReaderSeparatorModel.Metrics.destination)

        case .startOfSeries:
            VStack(spacing: dimensions.spacing.space2) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Start of series")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(height: ReaderSeparatorModel.Metrics.destination)
        }
    }

    var Action: some View {
        Group {
            if model.action == .retry {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.glassProminent)
            }
        }
        .frame(height: ReaderSeparatorModel.Metrics.action)
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

private extension ReaderSeparatorModel.Gap {
    var summary: String {
        count == 1
            ? "Chapter \(from.formatted()) is missing"
            : "Chapters \(from.formatted())–\(to.formatted()) are missing"
    }
}

// MARK: - Previews

// the separator has no orientation input - it renders identically in every
// reading mode. its axes are direction and destination state, so those are
// what the previews cover
#Preview("Forward") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: "The Gathering Storm"),
            continuity: nil,
            gap: nil,
            destination: .chapter(number: 45, title: "Aftermath")
        ),
        onRetry: {}
    )
}

#Preview("Backward") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .backward,
            terminal: .init(number: 45, title: "Aftermath"),
            continuity: nil,
            gap: nil,
            destination: .chapter(number: 44, title: "The Gathering Storm")
        ),
        onRetry: {}
    )
}

#Preview("Event Recording") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: ""),
            continuity: nil,
            gap: nil,
            destination: .chapter(number: 45, title: ""),
            event: .recording
        ),
        onRetry: {}
    )
}

#Preview("Event Recorded") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: ""),
            continuity: nil,
            gap: nil,
            destination: .chapter(number: 45, title: ""),
            event: .recorded
        ),
        onRetry: {}
    )
}

#Preview("Event Flow") {
    @Previewable @State var event: ReaderSeparatorModel.EventStatus?

    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: ""),
            continuity: nil,
            gap: nil,
            destination: .chapter(number: 45, title: ""),
            event: event
        ),
        onRetry: {}
    )
    .task {
        try? await Task.sleep(for: .seconds(1))
        event = .recording
        try? await Task.sleep(for: .seconds(1.5))
        event = .recorded
    }
}

#Preview("Full Stack") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: "The Gathering Storm"),
            continuity: .init(source: "MangaDex", scanlator: "Asura Scans", language: "EN"),
            gap: .init(from: 45, to: 49, count: 5),
            destination: .chapter(number: 50, title: "Return")
        ),
        onRetry: {}
    )
}

#Preview("Loading") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: ""),
            continuity: nil,
            gap: nil,
            destination: .loading(number: 45)
        ),
        onRetry: {}
    )
}

#Preview("Failed") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: ""),
            continuity: nil,
            gap: nil,
            destination: .failed(.offline(2))
        ),
        onRetry: {}
    )
}

#Preview("Caught Up") {
    ReaderSeparatorView(
        model: .init(
            boundary: .after(1),
            direction: .forward,
            terminal: .init(number: 44, title: ""),
            continuity: nil,
            gap: nil,
            destination: .caughtUp
        ),
        onRetry: {}
    )
}

#Preview("Start of Series") {
    ReaderSeparatorView(
        model: .init(
            boundary: .start,
            direction: .backward,
            terminal: nil,
            continuity: nil,
            gap: nil,
            destination: .startOfSeries
        ),
        onRetry: {}
    )
}

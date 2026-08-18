//
//  DetailsRefreshPill.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import SwiftUI

struct DetailsRefreshPill: View {
    let outcomes: [DetailsComposer.Refresh.Outcome]
    let refresher: Compositor.Refresh

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let badge: CGFloat = 20
        static let width: CGFloat = 320
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            ForEach(outcomes) { outcome in
                Row(outcome)
            }
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .frame(maxWidth: Layout.width, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: dimensions.radius.radius16))
        .padding(dimensions.screenMargin)
    }

    private func Row(_ outcome: DetailsComposer.Refresh.Outcome) -> some View {
        let started = refresher.isChecking(origin: outcome.id)

        return HStack(spacing: dimensions.spacing.space8) {
            Icon(outcome, started: started)

            Text(outcome.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Message(outcome.result, started: started)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func Icon(_ outcome: DetailsComposer.Refresh.Outcome, started: Bool) -> some View {
        Group {
            switch outcome.result {
            // waiting for a host slot is not the same as talking to the host -
            // a spinner before anything has begun is the small lie that makes
            // a slow refresh look stuck
            case nil where !started:
                Image(systemName: "clock")
                    .foregroundStyle(.muted)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case nil:
                Image(systemName: "progress.indicator")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .added:
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.success)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            // not a checkmark - that reads as an achievement the source
            // did not earn
            case .unchanged:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.muted)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.warning)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .cancelled:
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.muted)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .frame(width: Layout.badge, height: Layout.badge)
        .animation(.settle, value: outcome.result)
        .animation(.settle, value: started)
    }

    @ViewBuilder
    private func Message(_ result: OriginRefresher.Outcome?, started: Bool) -> some View {
        switch result {
        case nil: Text(started ? "Checking" : "Queued")
        case .added(let count): Text("^[\(count) new chapter](inflect: true)")
        case .unchanged: Text("Up to date")
        case .failed(let reason): Text(reason)
        case .cancelled: Text("Stopped")
        }
    }
}

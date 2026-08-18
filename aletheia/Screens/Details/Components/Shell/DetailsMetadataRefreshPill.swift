//
//  DetailsMetadataRefreshPill.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import SwiftUI

// the metadata counterpart to DetailsRefreshPill - one row per source and per
// linked tracker, each answering for itself. no queued/checking split like
// the chapter pill has: metadata refresh has no host-gate visibility hook to
// read, so every unanswered row is simply "checking"
struct DetailsMetadataRefreshPill: View {
    let outcomes: [DetailsComposer.Refresh.MetadataOutcomeRow]

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

    private func Row(_ outcome: DetailsComposer.Refresh.MetadataOutcomeRow) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Icon(outcome.result)

            Text(outcome.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Message(outcome.result)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func Icon(_ result: MetadataOutcome?) -> some View {
        Group {
            switch result {
            case nil:
                Image(systemName: "progress.indicator")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .updated:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.success)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            // the inverse of updated, same vocabulary DetailsRefreshPill uses
            // for unchanged chapters - not a tick, which reads as an
            // achievement the supplier did not earn
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
        .animation(.settle, value: result)
    }

    @ViewBuilder
    private func Message(_ result: MetadataOutcome?) -> some View {
        switch result {
        case nil: Text("Checking")
        case .updated: Text("Updated")
        case .unchanged: Text("Up to date")
        case .failed(let reason): Text(reason)
        case .cancelled: Text("Stopped")
        }
    }
}

// MARK: - Previews

#Preview {
    DetailsMetadataRefreshPill(outcomes: [
        .init(id: .origin(1), name: "MangaDex", result: .updated),
        .init(id: .origin(2), name: "MangaFire", result: .unchanged),
        .init(id: .tracker(.anilist), name: "AniList", result: nil),
        .init(
            id: .tracker(.myAnimeList), name: "MyAnimeList",
            result: .failed("Couldn't reach the service.")),
    ])
    .padding()
    .background(.canvas)
}

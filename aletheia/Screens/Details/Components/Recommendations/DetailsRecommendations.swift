//
//  DetailsRecommendations.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import SwiftUI
import Tagged

// titles like this one, from the on-device content model. the rail carries cover
// and title only - a recommendation is a series the reader does not own, so
// everything else about it belongs in the sheet a tap opens rather than crowding
// twenty cards with metadata nobody reads at this size
struct DetailsRecommendations: View {
    let phase: LoadPhase
    let results: [Recommendation]
    let onOpen: (Recommendation) -> Void
    var context: DetailsComposer.Recommendations.ImpressionContext? = nil

    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor

    private enum Layout {
        static let skeletonCount = 6
        static let carouselVisible = 3
        // half the card. a sliver at the screen edge is not something a reader
        // took in, and counting it would put "never seen" back beside "seen and
        // passed over" - which is the one distinction this exists to make
        static let seenFraction: Double = 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Similar Titles")

            ZStack(alignment: .topLeading) {
                switch phase {
                case .pending:
                    Rail {
                        ForEach(0..<Layout.skeletonCount, id: \.self) { _ in Slot { SourceCard() } }
                    }
                    .scrollDisabled(true)
                    .shimmer()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                case .content:
                    Rail {
                        ForEach(Array(results.enumerated()), id: \.element.id) { rank, result in
                            Slot {
                                Card(result: result)
                                    .onScrollVisibilityChange(threshold: Layout.seenFraction) { visible in
                                        guard visible, let context else { return }
                                        compositor.impressions.shown(
                                            result,
                                            rank: rank,
                                            batchId: context.batchId,
                                            seed: context.series,
                                            seedCatalogId: context.seedCatalogId,
                                            modelVersion: context.modelVersion,
                                            alreadyInLibrary: context.owned.contains(result.catalogId))
                                    }
                                    .tappable {
                                        if let context {
                                            compositor.impressions.tapped(
                                                catalogId: result.catalogId,
                                                batchId: context.batchId)
                                        }
                                        onOpen(result)
                                    }
                            }
                        }
                    }
                    .transition(.opacity)
                case .empty, .failed:
                    // no action, deliberately. there is nothing a reader can do
                    // about a title the catalogue does not carry, and a retry
                    // that cannot change the answer is worse than no button
                    Text("Nothing similar found for this title.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, dimensions.spacing.space8)
                        .transition(.opacity)
                }
            }
            .animation(.settle, value: phase)
        }
    }

    // SourceCard plus the two numbers only a recommendation has. the confidence
    // takes the corner mark the library and source cards spend on state, since
    // that is the fact about the artwork a reader is scanning for; the score is
    // not on the artwork at all - it is a z-score against this one seed, so it
    // cannot be compared with the card beside it and must not read as a rank
    private func Card(result: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
            SourceCard(stub: result.stub)
                .overlay(alignment: .topTrailing) {
                    Badge(text: result.confidence.percent, tone: .neutral, size: .compact)
                        .padding(dimensions.spacing.space8)
                }

            Text("z \(result.score.formatted(.number.precision(.fractionLength(2))))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func Rail<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: dimensions.spacing.space12) {
                content()
            }
        }
    }

    // one card per slot, sized off the rail rather than a literal, so a
    // recommendation card and a preset card are the same width on the same screen
    private func Slot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .containerRelativeFrame(
                .horizontal,
                count: Layout.carouselVisible,
                spacing: dimensions.spacing.space12
            )
    }
}

private extension Recommendation {
    // SourceCard draws a stub, and a recommendation is one in everything the card
    // reads. the slug is the catalogue id because nothing here routes by slug -
    // the tap hands back the Recommendation itself
    var stub: SeriesStub {
        SeriesStub(slug: String(catalogId.rawValue), title: title, cover: cover)
    }
}

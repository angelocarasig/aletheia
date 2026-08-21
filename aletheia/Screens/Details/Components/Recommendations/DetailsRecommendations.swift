//
//  DetailsRecommendations.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import SwiftUI
import Tagged

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
        // half the card, not a sliver - a "shown" impression must mean the
        // reader actually took it in, or "never seen" and "seen and passed
        // over" become indistinguishable in the impression data
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
                                    .onScrollVisibilityChange(threshold: Layout.seenFraction) {
                                        visible in
                                        guard visible, let context else { return }
                                        compositor.impressions.shown(
                                            result,
                                            rank: rank,
                                            batchId: context.batchId,
                                            seed: context.series,
                                            seedCatalogId: context.seedCatalogId,
                                            modelVersion: context.modelVersion,
                                            alreadyInLibrary: context.owned.contains(
                                                result.catalogId))
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

    // it is a z-score against this one seed, not comparable across cards, and
    // placing it like a badge would read as a rank
    private func Card(result: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
            SourceCard(stub: result.stub)

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

    private func Slot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .containerRelativeFrame(
                .horizontal,
                count: Layout.carouselVisible,
                spacing: dimensions.spacing.space12
            )
    }
}

extension Recommendation {
    // slug is the catalogue id, not a real routing slug - nothing here routes
    // by it, the tap hands back the Recommendation itself
    fileprivate var stub: SeriesStub {
        SeriesStub(slug: String(catalogId.rawValue), title: title, cover: cover)
    }
}

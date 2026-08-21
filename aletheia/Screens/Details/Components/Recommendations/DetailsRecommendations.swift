//
//  DetailsRecommendations.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import SwiftUI
import Tagged

struct DetailsRecommendations: View {
    let phase: RecommendationsPhase
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
                case .empty:
                    ContentUnavailableView(
                        "No Similar Titles",
                        systemImage: "sparkle.magnifyingglass",
                        description: Text("Nothing else in the catalogue matched closely enough.")
                    )
                    .transition(.opacity)
                case .noModel:
                    ContentUnavailableView(
                        "No Recommendation Model",
                        systemImage: "sparkles",
                        description: Text("Download a model in Settings to see titles like this one.")
                    )
                    .transition(.opacity)
                case .failed:
                    ContentUnavailableView(
                        "Couldn't Load Recommendations",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Something went wrong reading the recommendation data.")
                    )
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

// MARK: - Previews

#Preview {
    @Previewable @State var phase: RecommendationsPhase = .content

    NavigationStack {
        ScrollView {
            DetailsRecommendations(
                phase: phase,
                results: phase == .content ? .previewSample : [],
                onOpen: { _ in }
            )
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Phase", selection: $phase) {
                    Text("Pending").tag(RecommendationsPhase.pending)
                    Text("Content").tag(RecommendationsPhase.content)
                    Text("Empty").tag(RecommendationsPhase.empty)
                    Text("No Model").tag(RecommendationsPhase.noModel)
                    Text("Failed").tag(RecommendationsPhase.failed)
                }
            }
        }
    }
}

extension [Recommendation] {
    fileprivate static var previewSample: [Recommendation] {
        (0..<6).map { i in
            Recommendation(
                catalogId: CatalogID(rawValue: Int32(1000 + i)),
                row: i,
                title: "Sample Title \(i + 1)",
                authors: ["Author Name"],
                artists: ["Artist Name"],
                cover: nil,
                synopsis: "A short preview synopsis for sample title \(i + 1).",
                tags: ["Action", "Fantasy"],
                classification: .Safe,
                publication: .Ongoing,
                year: 2020 + i,
                format: .manga,
                register: .general,
                score: Float(3.4 - Double(i) * 0.2),
                confidence: 0,
                blocks: .init(tag: 0, embedding: 0, era: 0))
        }
    }
}

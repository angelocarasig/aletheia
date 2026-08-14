//
//  DetailsRecommendationSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import SwiftUI
import Kingfisher

// what the rail deliberately leaves out. everything here comes from the model
// bundle rather than the database - this is a series the reader almost certainly
// does not own, so there is no row to read and nothing to navigate to yet
struct DetailsRecommendationSheet: View {
    let result: Recommendation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverWidth: CGFloat = 120
        static let coverAspect: CGFloat = 11 / 16
        static let meterHeight: CGFloat = 6
        static let meterLabelWidth: CGFloat = 52
        static let meterValueWidth: CGFloat = 40
        static let trackOpacity: Double = 0.1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space20) {
                    header
                    if let synopsis = result.synopsis { self.synopsis(synopsis) }
                    if !result.tags.isEmpty { tags }
                    match
                }
                .padding(.horizontal, dimensions.spacing.space16)
                .padding(.bottom, dimensions.spacing.space32)
            }
            .navigationTitle("Similar Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: dimensions.spacing.space16) {
            KFImage(result.cover)
                .placeholder {
                    RoundedRectangle(cornerRadius: dimensions.radius.radius8, style: .continuous)
                        .fill(.primary.opacity(0.08))
                        .shimmer()
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: Layout.coverWidth,
                       height: Layout.coverWidth / Layout.coverAspect)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8, style: .continuous))

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Text(result.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                // authors and artists are separate in the catalogue and usually
                // the same person, so they are joined rather than labelled twice
                let people = Array(Set(result.authors + result.artists)).sorted()
                if !people.isEmpty {
                    Text(people.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FlowLayout(spacing: dimensions.spacing.space4) {
                    Badge(text: result.format.label, tone: .neutral, size: .compact)
                    // both carry the app's own tone rather than neutral - these
                    // are the two facts here that vary in a way worth colouring
                    Badge(text: result.publication.rawValue,
                          tone: result.publication.tone,
                          size: .compact)
                    Badge(text: result.classification.rawValue,
                          tone: result.classification.tone,
                          size: .compact)
                    if let year = result.year {
                        // no grouping separator - a year is not a quantity
                        Badge(text: String(year), tone: .neutral, size: .compact)
                    }
                }
            }
        }
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            SectionHeader("Tags")
            // the model ranks on far more tags than a reader wants to read, and
            // they arrive in column order rather than by importance
            FlowLayout(spacing: dimensions.spacing.space4) {
                ForEach(result.tags.prefix(12), id: \.self) { tag in
                    Badge(text: tag, tone: .neutral)
                }
            }
        }
    }

    // what the number on the card is made of. three blocks rather than one bar,
    // because "shares your tags" and "reads like it" are different claims and a
    // reader can tell which one they trust. era is shown and deliberately
    // excluded from the confidence figure above it - a shared publication year
    // was reading as a content match
    private var match: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader(title: "Match") {
                Badge(text: result.confidence.percent, tone: .neutral, size: .compact)
            }

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Meter(label: "Tags", value: result.blocks.tag)
                Meter(label: "Story", value: result.blocks.embedding)
                Meter(label: "Era", value: result.blocks.era)
            }

            // a z-score against this seed's own field. states its own scope
            // because it is the one figure here that means nothing next to
            // another recommendation's
            Text("Ranked \(result.score.formatted(.number.precision(.fractionLength(2)))) above average for this title.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func Meter(label: String, value: Float) -> some View {
        let fraction = Double(min(max(value, 0), 1))

        return HStack(spacing: dimensions.spacing.space12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Layout.meterLabelWidth, alignment: .leading)

            Capsule()
                .fill(.primary.opacity(Layout.trackOpacity))
                .frame(height: Layout.meterHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.brand)
                            .frame(width: proxy.size.width * fraction)
                    }
                }

            Text(value.percent)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Layout.meterValueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.percent)
    }

    private func synopsis(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            SectionHeader("Synopsis")
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension Float {
    // the blocks and the confidence are all 0...1 quantities read at a glance
    // beside each other, so they are formatted in one place rather than four
    var percent: String {
        Double(min(max(self, 0), 1)).formatted(.percent.precision(.fractionLength(0)))
    }
}

private extension CatalogFormat {
    var label: String {
        switch self {
        case .manga: "Manga"
        case .manhwa: "Manhwa"
        case .manhua: "Manhua"
        case .oel: "OEL"
        case .novel: "Novel"
        case .other: "Other"
        }
    }
}

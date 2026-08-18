//
//  SourceCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Kingfisher
import SwiftUI

struct SourceCard: View {
    var stub: SeriesStub?
    var referer: URL?
    var match: SeriesMatch?
    // resolved by the caller, not computed here - otherwise cards in the same
    // grid could disagree on whether they're obscured
    var obscured: Bool = false
    var selected: Bool = false

    @Environment(\.dimensions) private var dimensions
    // DownsamplingImageProcessor's scale defaults to 1 - without this, retina
    // slots decode at a third of their resolution
    @Environment(\.displayScale) private var displayScale

    @State private var slot: CGSize = .zero

    private enum Layout {
        static let coverAspect: CGFloat = 11 / 16
        static let titleLines = 2
        static let scrimOpacity: Double = 0.55
        static let titleHeight: CGFloat = 12
        static let subtitleHeight: CGFloat = 10
        static let subtitleWidthFactor: CGFloat = 0.6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Cover
            Title
        }
    }

    @ViewBuilder
    private var Cover: some View {
        Color.clear
            .aspectRatio(Layout.coverAspect, contentMode: .fit)
            // rounded because size is part of the downsampler's cache key - a
            // fractional point mints a fresh decode every layout pass
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(width: proxy.size.width.rounded(), height: proxy.size.height.rounded())
            } action: {
                slot = $0
            }
            .overlay {
                if let cover = stub?.cover {
                    // slot is zero until the first layout pass - DownsamplingImageProcessor
                    // built on a zero size caches under a size that describes nothing
                    if slot.width > 0 {
                        KFImage(cover)
                            .requestModifier(AnyModifier.referer(referer))
                            .setProcessor(DownsamplingImageProcessor(size: slot))
                            .scaleFactor(displayScale)
                            .backgroundDecode()
                            .resizable()
                            .placeholder { Placeholder.shimmer() }
                            .fade(duration: 0.25)
                            .scaledToFill()
                    } else {
                        Placeholder.shimmer()
                    }
                } else {
                    Placeholder
                }
            }
            // obscured must apply before the badge overlays, or the match
            // marker - our own annotation, not artwork - gets blurred too
            .obscured(obscured)
            .overlay { Badge }
            .overlay { Selected }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
    }

    @ViewBuilder
    private var Title: some View {
        if let title = stub?.title {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(Layout.titleLines, reservesSpace: true)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Bar(height: Layout.titleHeight)
                Bar(height: Layout.subtitleHeight)
                    .scaleEffect(x: Layout.subtitleWidthFactor, anchor: .leading)
            }
        }
    }

    // deliberately unshimmered here - callers rendering a grid of empty cards
    // apply .shimmer() to the container so the sweep runs across the whole grid
    private var Placeholder: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
    }

    private func Bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: dimensions.radius.radius4)
            .fill(.primary.opacity(0.1))
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var Selected: some View {
        if selected {
            Color.black.opacity(Layout.scrimOpacity)
                .overlay {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.success)
                }
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var Badge: some View {
        switch match?.outcome {
        case .inLibrary:
            Marker(systemImage: "checkmark.circle.fill", tint: .success)
        case .candidates:
            Marker(systemImage: "circle.lefthalf.filled", tint: .brand)
        case .unmatched, nil:
            EmptyView()
        }
    }

    private func Marker(systemImage: String, tint: Color) -> some View {
        Color.black.opacity(Layout.scrimOpacity)
            .overlay(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .padding(dimensions.spacing.space8)
            }
    }

}

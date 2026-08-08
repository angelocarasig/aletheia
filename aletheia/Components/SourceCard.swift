//
//  SourceCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import Kingfisher

struct SourceCard: View {
    var stub: SeriesStub?
    var referer: URL?
    var match: SeriesMatch?
    // resolved by the caller from the preference and the reveal switch together,
    // so the card never reads either and a grid cannot disagree with itself
    var obscured: Bool = false

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverAspect: CGFloat = 11 / 16
        static let titleLines = 2
        static let scrimOpacity: Double = 0.55
        static let titleHeight: CGFloat = 12
        static let subtitleHeight: CGFloat = 10
        static let subtitleWidthFactor: CGFloat = 0.6
        // the artwork must not be legible through it, and a blurred cover still
        // has to read as a cover rather than as a failed load
        static let blurRadius: CGFloat = 24
        static let blurScrim: Double = 0.15
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
            .overlay {
                if let cover = stub?.cover {
                    KFImage(cover)
                        .requestModifier(AnyModifier.referer(referer))
                        .resizable()
                        .placeholder { Placeholder.shimmer() }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Placeholder
                }
            }
            // blur before the badge, so a match marker stays readable on a
            // covered card - it is our own annotation, not the artwork
            .blur(radius: obscured ? Layout.blurRadius : 0)
            .overlay {
                if obscured {
                    Rectangle().fill(.black.opacity(Layout.blurScrim))
                }
            }
            .overlay { Badge }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
            .animation(.smooth(duration: 0.25), value: obscured)
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
            // stands in for the two lines the real title reserves
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Bar(height: Layout.titleHeight)
                Bar(height: Layout.subtitleHeight)
                    .scaleEffect(x: Layout.subtitleWidthFactor, anchor: .leading)
            }
        }
    }

    // unshimmered on its own - callers rendering a full grid of empty cards apply
    // .shimmer() to the container so the sweep runs across the whole grid
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

    // only states worth acting on are marked - an unmatched result stays silent.
    // both states share one treatment so they read as the same kind of signal
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

    // the scrim carries the state at a glance and the corner mark says which one,
    // so the artwork stays readable underneath instead of hosting a centred icon
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

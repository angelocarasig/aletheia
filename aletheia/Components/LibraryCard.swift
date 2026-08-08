//
//  LibraryCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Kingfisher

// the library counterpart to SourceCard. a series here is already owned, so it
// carries nothing about where it came from and no match state - what matters is
// how much of it is left to read
struct LibraryCard: View {
    var title: String?
    var cover: URL?
    var unreadCount: Int = 0

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverAspect: CGFloat = 11 / 16
        static let titleLines = 2
        static let titleHeight: CGFloat = 12
        static let subtitleHeight: CGFloat = 10
        static let subtitleWidthFactor: CGFloat = 0.6
        static let placeholderOpacity: Double = 0.1
        static let badgeCap = 99
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
                if let cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder { Placeholder.shimmer() }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Placeholder
                }
            }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
            // outside the clip so the badge is not cut by the corner radius
            .overlay(alignment: .topTrailing) { Unread }
    }

    @ViewBuilder
    private var Unread: some View {
        if unreadCount > 0 {
            Text(unreadCount > Layout.badgeCap ? "\(Layout.badgeCap)+" : "\(unreadCount)")
                .font(.caption2)
                .fontWeight(.bold)
                // red rather than brand: this is a notification count, and red is
                // what a count on artwork reads as everywhere else on the platform.
                // onBrand is plain white, which is the right contrast on red too
                .foregroundStyle(.onBrand)
                .padding(.horizontal, dimensions.spacing.space8)
                .padding(.vertical, dimensions.spacing.space2)
                .background(.danger, in: .capsule)
                .padding(dimensions.spacing.space4)
        }
    }

    @ViewBuilder
    private var Title: some View {
        if let title {
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
            .fill(.primary.opacity(Layout.placeholderOpacity))
    }

    private func Bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: dimensions.radius.radius4)
            .fill(.primary.opacity(Layout.placeholderOpacity))
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

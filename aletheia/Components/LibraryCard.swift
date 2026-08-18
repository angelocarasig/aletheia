//
//  LibraryCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Kingfisher
import SwiftUI

struct LibraryCard: View {
    var title: String?
    var cover: URL?
    var unreadCount: Int = 0
    var activity: Activity?
    // resolved by the caller, not computed here - otherwise cards in the same
    // grid could disagree on whether they're obscured
    var obscured: Bool = false

    enum Activity {
        case queued
        case checking
    }

    @Environment(\.dimensions) private var dimensions
    // DownsamplingImageProcessor's scale defaults to 1 - without this, retina
    // slots decode at a third of their resolution
    @Environment(\.displayScale) private var displayScale

    // cleared on url change - a recycled cell must drop the previous blank
    @State private var unavailable = false
    @State private var slot: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let coverAspect: CGFloat = 11 / 16
        static let titleLines = 2
        static let titleHeight: CGFloat = 12
        static let subtitleHeight: CGFloat = 10
        static let subtitleWidthFactor: CGFloat = 0.6
        static let placeholderOpacity: Double = 0.1
        static let badgeCap = 99
        static let scrimOpacity: Double = 0.45
        static let queuedScrimOpacity: Double = 0.3
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
                if let cover {
                    // slot is zero until the first layout pass - DownsamplingImageProcessor
                    // built on a zero size caches under a size that describes nothing
                    if slot.width > 0 {
                        KFImage(cover)
                            .setProcessor(DownsamplingImageProcessor(size: slot))
                            .scaleFactor(displayScale)
                            .backgroundDecode()
                            .resizable()
                            .placeholder { Placeholder.shimmer() }
                            .onFailure { _ in unavailable = true }
                            .fade(duration: 0.25)
                            .scaledToFill()
                            .opacity(unavailable ? 0 : 1)
                            .overlay { if unavailable { Missing } }
                            .onChange(of: cover) { unavailable = false }
                    } else {
                        Placeholder.shimmer()
                    }
                } else {
                    Placeholder
                }
            }
            // obscured must apply before the activity overlay, or the checking
            // mark - our own annotation, not artwork - gets blurred with the cover
            .obscured(obscured)
            .overlay { Checking }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
            // overlay after clipShape so the badge isn't cut by the corner radius
            .overlay(alignment: .topTrailing) { Unread }
            .animation(.settle, value: activity)
    }

    @ViewBuilder
    private var Checking: some View {
        switch activity {
        case .checking:
            Color.black.opacity(Layout.scrimOpacity)
                .overlay {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title)
                        .foregroundStyle(.brand)
                        // continuous, not the default stepped rotation - stepped
                        // reads as stuttering on a long-running check
                        .symbolEffect(
                            .rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                }
                .transition(.opacity)

        case .queued:
            Color.black.opacity(Layout.queuedScrimOpacity)
                .overlay {
                    Image(systemName: "clock")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .transition(.opacity)

        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var Unread: some View {
        if unreadCount > 0 {
            Text(unreadCount > Layout.badgeCap ? "\(Layout.badgeCap)+" : "\(unreadCount)")
                .font(.caption2)
                .fontWeight(.bold)
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
            .fill(.primary.opacity(Layout.placeholderOpacity))
    }

    private var Missing: some View {
        Placeholder.overlay {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    private func Bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: dimensions.radius.radius4)
            .fill(.primary.opacity(Layout.placeholderOpacity))
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

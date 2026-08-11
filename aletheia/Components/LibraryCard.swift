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
    var activity: Activity?
    // resolved by the caller from the preference and the reveal together, so the
    // card never reads either and a grid cannot disagree with itself
    var obscured: Bool = false

    // the same two words the details pill uses: waiting for its turn, or being
    // talked to right now. a card with neither is not in a run at all
    enum Activity {
        case queued
        case checking
    }

    @Environment(\.dimensions) private var dimensions

    // cleared when the url changes, or a recycled cell hands the next series the
    // previous one's blank
    @State private var unavailable = false
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
        // lighter, because waiting is a weaker claim on the card than being
        // worked on - the two have to be distinguishable at a glance across a
        // grid, not just on the one you are looking at
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
            .overlay {
                if let cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder { Placeholder.shimmer() }
                        // a permanently dead url left the shimmer up forever,
                        // which reads as a card still loading rather than one
                        // with no artwork
                        .onFailure { _ in unavailable = true }
                        .fade(duration: 0.25)
                        .scaledToFill()
                        .opacity(unavailable ? 0 : 1)
                        .overlay { if unavailable { Missing } }
                        .onChange(of: cover) { unavailable = false }
                } else {
                    Placeholder
                }
            }
            // blur before the activity mark, so a card being checked still says
            // so on a covered cover - it is our own annotation, not the artwork
            .obscured(obscured)
            .overlay { Checking }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
            // outside the clip so the badge is not cut by the corner radius
            .overlay(alignment: .topTrailing) { Unread }
            // the scrim fades rather than snapping - a card entering and leaving
            // the run is the most frequent state change on this screen
            .animation(.settle, value: activity)
    }

    // the SourceCard treatment: a scrim carries the state at a glance and a mark
    // says which one, so the artwork stays readable underneath. centred and
    // spinning rather than a corner glyph, because this one is happening now
    // rather than being a fact about the series
    @ViewBuilder
    private var Checking: some View {
        switch activity {
        case .checking:
            Color.black.opacity(Layout.scrimOpacity)
                .overlay {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title)
                        .foregroundStyle(.brand)
                        // continuous rather than the default stepped rotation,
                        // which reads as stuttering on a long-running check.
                        // the scrim already says the card is busy, so with
                        // reduce motion on the symbol simply holds still
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
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

    // quiet on purpose: artwork that will not load is not something the reader
    // can act on. the card still names the series and still opens it
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

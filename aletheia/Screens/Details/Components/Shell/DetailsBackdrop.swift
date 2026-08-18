//
//  DetailsBackdrop.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Kingfisher
import SwiftUI

// its own reference type so only the backdrop observes it - held as state beside
// the scroll view, every update would re-evaluate a body holding every chapter
@MainActor
@Observable
final class DetailsScroll {
    var offset: CGFloat = 0
}

extension DetailsBackdrop {
    // read by the scroll spacer and the skeleton too, so the three stay aligned
    static let heroHeight: CGFloat = 200

    // how far you scroll before the blur and the dim reach full strength.
    // points, never a fraction of the content: a 1925 chapter series and an 8
    // chapter one must feel identical
    static let blurDistance: CGFloat = 200

    // the scroll callback only fires when its value changes, so rounding bounds
    // the blur to a few dozen updates rather than one a frame
    static let blurStep: CGFloat = 8
}

struct DetailsBackdrop: View {
    let cover: URL?
    let referer: URL?
    let scroll: DetailsScroll
    // how far you scroll before the blur and the dim are at full strength. this
    // is per-surface because a screen with a tall header has further to scroll
    // before the artwork is in the way, and the caller's own clamp has to use
    // the same distance, which is why it is passed rather than read off the type
    var blurDistance: CGFloat = DetailsBackdrop.blurDistance

    // where the artwork fades out, as fractions of its own 700pt height: 0 is
    // its top edge, 1 its bottom. above fadeStart it is untouched, below fadeEnd
    // it is gone, and between them it is on its way out.
    //
    // lowering BOTH moves the whole fade up. lowering only fadeStart makes the
    // fade longer, which is softer rather than higher - the mistake that is easy
    // to make here, because it looks like nothing moved
    var fadeStart: CGFloat = Layout.fadeStart
    var fadeEnd: CGFloat = Layout.fadeEnd

    @Environment(\.colorScheme) private var colorScheme

    fileprivate enum Layout {
        static let height: CGFloat = 700
        static let fadeStart: CGFloat = 0.50
        static let fadeEnd: CGFloat = 1
        static let fadeDuration: Double = 0.25
        static let placeholderOpacity: Double = 0.1
        static let sample = CGSize(width: 120, height: 180)
        static let radius: CGFloat = 12

        // white washes artwork out faster than black darkens it, so light needs
        // a gentler range for the same perceived effect
        enum Dim {
            static let dark: ClosedRange<Double> = 0.20...0.65
            static let light: ClosedRange<Double> = 0.08...0.40
        }
    }

    // downsampled first - kingfisher blurs on the CPU at full pixel size, a real
    // hitch on a 6MP cover for detail this radius discards anyway
    private static let softened: any ImageProcessor =
        DownsamplingImageProcessor(size: Layout.sample)
        |> BlurImageProcessor(blurRadius: Layout.radius)

    private var progress: Double {
        min(max(scroll.offset / blurDistance, 0), 1)
    }

    private var dim: Double {
        let range = colorScheme == .dark ? Layout.Dim.dark : Layout.Dim.light
        return range.lowerBound + progress * (range.upperBound - range.lowerBound)
    }

    // a pre-blurred copy crossfades over the sharp one: animating a blur radius
    // re-runs a full screen convolution every frame, opacity does not
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Artwork(geometry.size)

                Artwork(geometry.size, processor: Self.softened)
                    .opacity(progress)

                Fade

                Palette.canvas
                    .opacity(dim)
            }
            .frame(width: geometry.size.width, height: Layout.height)
            .clipped()
            .ignoresSafeArea()
        }
    }

    private func Artwork(_ size: CGSize, processor: (any ImageProcessor)? = nil) -> some View {
        // the animation sits on this stable Color.clear ancestor, not on the
        // image: .id(cover) replaces the KFImage, so an animation modifier on the
        // image itself is torn down with it and never drives the transition. keyed
        // on cover alone, so it never fires on the scroll-driven blur opacity
        Color.clear
            .frame(width: size.width, height: Layout.height)
            .overlay {
                KFImage(cover)
                    .requestModifier(AnyModifier.referer(referer))
                    .setProcessor(processor ?? DefaultImageProcessor.default)
                    .resizable()
                    .placeholder { Placeholder }
                    .fade(duration: Layout.fadeDuration)
                    .scaledToFill()
                    .id(cover)
                    .transition(.opacity)
            }
            .clipped()
            .animation(.settle, value: cover)
    }

    private var Placeholder: some View {
        Rectangle()
            .fill(.primary.opacity(Layout.placeholderOpacity))
            .shimmer()
    }

    // see-through at fadeStart, solid canvas at fadeEnd
    private var Fade: some View {
        LinearGradient(
            colors: [.clear, Palette.canvas],
            startPoint: UnitPoint(x: 0.5, y: fadeStart),
            endPoint: UnitPoint(x: 0.5, y: fadeEnd)
        )
    }
}

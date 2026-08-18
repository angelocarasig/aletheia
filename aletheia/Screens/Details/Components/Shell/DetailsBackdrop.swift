//
//  DetailsBackdrop.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Kingfisher
import SwiftUI

// its own reference type so only the backdrop observes it - as @State beside
// the scroll view, every scroll update would re-evaluate a body holding
// every chapter
@MainActor
@Observable
final class DetailsScroll {
    var offset: CGFloat = 0
}

extension DetailsBackdrop {
    // read by the scroll spacer and the skeleton too, so the three stay aligned
    static let heroHeight: CGFloat = 200

    // points, never a fraction of content height - a 1925 chapter series and
    // an 8 chapter one must feel identical
    static let blurDistance: CGFloat = 200

    // rounds the scroll offset so the callback (which only fires on change)
    // fires a few dozen times rather than once a frame
    static let blurStep: CGFloat = 8
}

struct DetailsBackdrop: View {
    let cover: URL?
    let referer: URL?
    let scroll: DetailsScroll
    // passed rather than read off the type - per-surface, because a caller
    // with a taller header needs its own clamp to agree with this distance
    var blurDistance: CGFloat = DetailsBackdrop.blurDistance

    // fractions of the artwork's own 700pt height: 0 is its top edge, 1 its
    // bottom. lowering BOTH moves the whole fade up; lowering only fadeStart
    // makes the fade longer (softer, not higher) - easy to mistake for no
    // change at all
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

        // white washes artwork out faster than black darkens it, so light
        // needs a gentler range for the same perceived effect
        enum Dim {
            static let dark: ClosedRange<Double> = 0.20...0.65
            static let light: ClosedRange<Double> = 0.08...0.40
        }
    }

    // downsampled first - Kingfisher blurs on the CPU at full pixel size,
    // which hitches on a 6MP cover for detail this radius discards anyway
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

    // a pre-blurred copy crossfades over the sharp one - animating a blur
    // radius directly re-runs a full-screen convolution every frame, opacity
    // does not
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
        // animation sits on this stable Color.clear ancestor, not the image -
        // .id(cover) replaces the KFImage, so an animation on the image itself
        // would be torn down with it and never drive the transition
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

    private var Fade: some View {
        LinearGradient(
            colors: [.clear, Palette.canvas],
            startPoint: UnitPoint(x: 0.5, y: fadeStart),
            endPoint: UnitPoint(x: 0.5, y: fadeEnd)
        )
    }
}

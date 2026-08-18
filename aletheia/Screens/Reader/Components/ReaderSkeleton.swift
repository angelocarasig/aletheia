//
//  ReaderSkeleton.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// stands in for the reader while the first chapter resolves. the shapes match
// where the real chrome lands, so the swap does not move anything the eye is
// already tracking.
//
// deliberately not a copy of the overlay - v2 forked its whole control card
// into a shimmering twin and paid 483 lines to keep two layouts in step. this
// only draws the landmarks
struct ReaderSkeleton: View {
    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let page: CGFloat = 1.435
        static let control: CGFloat = 44
        static let identity: CGFloat = 180
        static let card: CGFloat = 116
        static let fill: Double = 0.12
    }

    var body: some View {
        ZStack {
            Page

            VStack {
                Header
                Spacer(minLength: 0)
                Card
            }
            .padding(dimensions.screenMargin)
        }
        .shimmer()
    }
}

extension ReaderSkeleton {
    // one page-shaped block rather than a strip: the real first page lands
    // before a second one would ever be visible
    fileprivate var Page: some View {
        GeometryReader { proxy in
            Block(cornerRadius: 0)
                .frame(
                    width: proxy.size.width,
                    height: min(proxy.size.height, proxy.size.width * Layout.page)
                )
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    fileprivate var Header: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Block(cornerRadius: Layout.control / 2)
                .frame(width: Layout.control, height: Layout.control)

            Block(cornerRadius: Layout.control / 2)
                .frame(width: Layout.identity, height: Layout.control)

            Spacer(minLength: 0)

            Block(cornerRadius: Layout.control / 2)
                .frame(width: Layout.control, height: Layout.control)

            Block(cornerRadius: Layout.control / 2)
                .frame(width: Layout.control, height: Layout.control)
        }
    }

    fileprivate var Card: some View {
        Block(cornerRadius: dimensions.radius.radius28)
            .frame(height: Layout.card)
    }

    fileprivate func Block(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.white.opacity(Layout.fill))
    }
}

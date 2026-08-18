//
//  DetailsSkeleton.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

// nothing real is shown before the series resolves - matching can land on a
// different series than the stub that opened it, and the stub's title/cover
// would then visibly change under the reader
struct DetailsSkeleton: View {
    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let heroSpacer: CGFloat = DetailsBackdrop.heroHeight
        static let lastLineInset: CGFloat = 200
        static let coverWidth: CGFloat = 140
        static let coverAspect: CGFloat = 11 / 16
        static let titleHeight: CGFloat = 24
        static let lineHeight: CGFloat = 12
        static let actionHeight: CGFloat = 50
        static let chipHeight: CGFloat = 28
        static let rowHeight: CGFloat = 56
        static let synopsisLines = 4
        static let chips = 5
        static let rows = 4
        static let fillOpacity: Double = 0.1
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space20) {
                Spacer()
                    .frame(height: Layout.heroSpacer)

                Header
                Actions
                Synopsis
                Chips
                Rows
            }
            .padding(.horizontal, dimensions.spacing.space8)
            .padding(.bottom, dimensions.spacing.space48)
        }
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var Header: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Block(cornerRadius: dimensions.radius.radius16)
                .aspectRatio(Layout.coverAspect, contentMode: .fit)
                .frame(width: Layout.coverWidth)

            Block().frame(height: Layout.titleHeight)
            Block().frame(width: Layout.coverWidth, height: Layout.lineHeight)
        }
    }

    private var Actions: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Block(cornerRadius: dimensions.radius.radius12)
            Block(cornerRadius: dimensions.radius.radius12)
            Block(cornerRadius: dimensions.radius.radius12)
                .frame(width: Layout.actionHeight)
        }
        .frame(height: Layout.actionHeight)
    }

    private var Synopsis: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            ForEach(0..<Layout.synopsisLines, id: \.self) { line in
                Block()
                    .frame(height: Layout.lineHeight)
                    .padding(.trailing, line == Layout.synopsisLines - 1 ? Layout.lastLineInset : 0)
            }
        }
    }

    private var Chips: some View {
        HStack(spacing: dimensions.spacing.space8) {
            ForEach(0..<Layout.chips, id: \.self) { _ in
                Block(cornerRadius: dimensions.radius.capsule)
                    .frame(height: Layout.chipHeight)
            }
        }
    }

    private var Rows: some View {
        VStack(spacing: dimensions.spacing.space12) {
            ForEach(0..<Layout.rows, id: \.self) { _ in
                Block(cornerRadius: dimensions.radius.radius12)
                    .frame(height: Layout.rowHeight)
            }
        }
    }

    private func Block(cornerRadius: CGFloat = 4) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.primary.opacity(Layout.fillOpacity))
    }
}

#Preview("Skeleton") {
    ZStack {
        Palette.canvas
            .ignoresSafeArea()

        DetailsSkeleton()
    }
}

#Preview("Skeleton over backdrop") {
    ZStack {
        Palette.canvas
            .ignoresSafeArea()

        DetailsBackdrop(
            cover: URL(string: "https://placehold.co/800x1200/png"),
            referer: nil,
            scroll: DetailsScroll()
        )

        DetailsSkeleton()
    }
}

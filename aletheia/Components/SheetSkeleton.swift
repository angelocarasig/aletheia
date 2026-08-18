//
//  SheetSkeleton.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

struct SheetSkeleton: View {
    var rows: Int = 8

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let barHeight: CGFloat = 10
        static let nameWidth: CGFloat = 140
        static let metaWidth: CGFloat = 90
        static let rowSpacing: CGFloat = 2
        static let fillOpacity: Double = 0.1
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Layout.rowSpacing) {
                ForEach(0..<rows, id: \.self) { _ in
                    Row
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .shimmer()
        }
        .scrollContentBackground(.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var Row: some View {
        HStack(spacing: dimensions.spacing.space12) {
            RoundedRectangle(cornerRadius: dimensions.radius.radius8)
                .fill(.primary.opacity(Layout.fillOpacity))
                .frame(width: Layout.iconSize, height: Layout.iconSize)

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Bar(Layout.nameWidth)
                Bar(Layout.metaWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(dimensions.spacing.space12)
    }

    private func Bar(_ width: CGFloat) -> some View {
        Capsule()
            .fill(.primary.opacity(Layout.fillOpacity))
            .frame(width: width, height: Layout.barHeight)
    }
}

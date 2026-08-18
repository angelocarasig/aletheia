//
//  ShelfRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 11/8/2026.
//

import Kingfisher
import SwiftUI
import Tagged

struct ShelfRow: View {
    let title: String
    let cover: URL?
    let detail: String
    let accessory: Text?
    let obscured: Bool

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverWidth: CGFloat = 44
        static let coverHeight: CGFloat = 60
        static let fillOpacity = 0.05
        static let placeholderOpacity = 0.1
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Cover

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let accessory {
                accessory
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.brandText)
                    .monospacedDigit()
                    .padding(.horizontal, dimensions.spacing.space8)
                    .padding(.vertical, dimensions.spacing.space4)
                    .background(Palette.brandSubtle, in: .capsule)
                    .allowsHitTesting(false)
            }
        }
        .padding(dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
    }

    private var Cover: some View {
        Color.clear
            .frame(width: Layout.coverWidth, height: Layout.coverHeight)
            .overlay {
                if let cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer()
                        }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .clipped()
            .obscured(obscured)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Shelf rows") {
    VStack(spacing: 12) {
        ShelfRow(
            title: "Vagabond",
            cover: nil,
            detail: "38% through Chapter 42",
            accessory: nil,
            obscured: false
        )

        ShelfRow(
            title: "Solo Leveling",
            cover: nil,
            detail: "Next up: Chapter 118",
            accessory: Text("14"),
            obscured: false
        )

        ShelfRow(
            title: "The Eminence in Shadow: I Am Going to Rule the World Behind the Scenes",
            cover: nil,
            detail: "Next up: Chapter 7",
            accessory: Text("112"),
            obscured: false
        )
    }
    .padding(16)
    .background(.canvas)
}

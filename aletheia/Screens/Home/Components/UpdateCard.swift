//
//  UpdateCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Kingfisher
import SwiftUI

struct UpdateCard: View {
    let title: String
    let cover: URL?
    let count: Int
    let latest: Date
    var obscured: Bool = false

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverAspect: CGFloat = 11 / 16
        static let coverWidth: CGFloat = 64
        static let titleLines = 2
        static let placeholderOpacity: Double = 0.1
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Cover

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(Layout.titleLines)
                    .multilineTextAlignment(.leading)

                Text("^[\(count) new chapter](inflect: true)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.brandText)

                LiveRelativeText(date: latest)
                    .font(.caption2)
                    .foregroundStyle(.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(dimensions.spacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    private var Cover: some View {
        Color.clear
            .aspectRatio(Layout.coverAspect, contentMode: .fit)
            .frame(width: Layout.coverWidth)
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
            .obscured(obscured)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }

    private var Placeholder: some View {
        Rectangle()
            .fill(.primary.opacity(Layout.placeholderOpacity))
    }
}

// MARK: - Previews

#Preview("Updates") {
    VStack(spacing: 12) {
        UpdateCard(title: "Blade of the Waning Moon", cover: nil, count: 3, latest: .now)
        UpdateCard(
            title: "Nine Lives of the Sword Saint Who Refused to Die",
            cover: nil,
            count: 1,
            latest: .now.addingTimeInterval(-7_200)
        )
        UpdateCard(
            title: "Café at the End of the Line", cover: nil, count: 12,
            latest: .now.addingTimeInterval(-86_400))
    }
    .padding(16)
    .background(.canvas)
}

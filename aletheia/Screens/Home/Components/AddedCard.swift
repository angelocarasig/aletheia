//
//  AddedCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Kingfisher
import SwiftUI

// a recently added series at the size the art deserves. Library shows many
// covers small; Home shows a few large, and says when each one arrived - the
// difference is scale and recency, not another poster wall
struct AddedCard: View {
    let title: String?
    let cover: URL?
    let unreadCount: Int
    let addedDate: Date?
    // resolved by the caller from the preference and the reveal together, so the
    // card never reads either and a rail cannot disagree with itself
    var obscured: Bool = false

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverAspect: CGFloat = 11 / 16
        static let placeholderOpacity: Double = 0.1
        static let badgeCap = 99
        static let titleHeight: CGFloat = 12
        static let subtitleHeight: CGFloat = 10
        static let subtitleWidthFactor: CGFloat = 0.6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Cover
            Caption
        }
    }

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
            .obscured(obscured)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
            // outside the clip so the badge is not cut by the corner radius
            .overlay(alignment: .topTrailing) { Unread }
    }

    @ViewBuilder
    private var Caption: some View {
        if let title {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let addedDate {
                    Text("Added \(addedDate.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Bar(height: Layout.titleHeight)
                Bar(height: Layout.subtitleHeight)
                    .scaleEffect(x: Layout.subtitleWidthFactor, anchor: .leading)
            }
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
                .padding(dimensions.spacing.space8)
        }
    }

    private var Placeholder: some View {
        Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
    }

    private func Bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: dimensions.radius.radius4)
            .fill(.primary.opacity(Layout.placeholderOpacity))
            .frame(height: height)
    }
}

#Preview {
    HStack(alignment: .top, spacing: 16) {
        AddedCard(
            title: "Blade of the Waning Moon",
            cover: nil,
            unreadCount: 7,
            addedDate: .now.addingTimeInterval(-2 * 24 * 60 * 60)
        )
        AddedCard(
            title: "Nine Lives of the Sword Saint",
            cover: nil,
            unreadCount: 0,
            addedDate: .now.addingTimeInterval(-5 * 24 * 60 * 60)
        )
    }
    .padding()
}

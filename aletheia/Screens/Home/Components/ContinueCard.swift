//
//  ContinueCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI
import Kingfisher
import Tagged

// a continue-reading entry: cover, title, and what tapping it opens. the
// subtitle names the outcome - resuming a partway chapter and starting the
// next unread one are different intents and the card says which
struct ContinueCard: View {
    let title: String
    let cover: URL?
    let unreadCount: Int
    let target: ContinueTarget
    // resolved by the caller from the preference and the reveal together, so the
    // card never reads either and a rail cannot disagree with itself
    var obscured: Bool = false

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverAspect: CGFloat = 11 / 16
        static let coverHeight: CGFloat = 140
        static let placeholderOpacity: Double = 0.1
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Cover

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // the one line that says this opens a chapter rather than a
                // screen about one - a reader could not tell which, and on a
                // resume rail that is the card's whole job. accented because
                // resume and start are different acts, not decoration
                HStack(spacing: dimensions.spacing.space4) {
                    Image(systemName: glyph)
                        .font(.caption)

                    Text(subtitle)
                        .font(.subheadline)
                }
                .foregroundStyle(Palette.brandText)

                if unreadCount > 0 {
                    Text("^[\(unreadCount) chapter](inflect: true) left")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(dimensions.spacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    // resuming and starting are different acts and get different marks: one
    // picks a book back up, the other opens it
    private var glyph: String {
        switch target {
        case .resume: "book.pages"
        case .start: "book.closed"
        }
    }

    private var subtitle: String {
        switch target {
        case let .resume(_, number, progress):
            "Continue Ch \(number.formatted()) · \(Int((progress * 100).rounded()))%"
        case let .start(_, number):
            "Start Ch \(number.formatted())"
        }
    }

    private var Cover: some View {
        Color.clear
            .aspectRatio(Layout.coverAspect, contentMode: .fit)
            .frame(height: Layout.coverHeight)
            .overlay {
                if let cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder { Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer() }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .obscured(obscured)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }
}

#Preview("Resume") {
    ContinueCard(
        title: "A Former Hero Returned From Another World",
        cover: nil,
        unreadCount: 12,
        target: .resume(chapterId: .init(rawValue: 1), number: 44, progress: 0.45)
    )
    .padding()
}

#Preview("Start Next") {
    ContinueCard(
        title: "Heavenly Solo Defender",
        cover: nil,
        unreadCount: 3,
        target: .start(chapterId: .init(rawValue: 1), number: 45)
    )
    .padding()
}

//
//  DetailsHeader.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import UIKit
import Kingfisher

struct DetailsHeader: View {
    let cover: URL?
    let referer: URL?
    let title: String
    let authors: [String]
    var onOpenCovers: () -> Void
    var onOpenTitles: () -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverWidth: CGFloat = 160
        static let coverAspect: CGFloat = 11 / 16
        static let fadeDuration: Double = 0.25
        static let placeholderOpacity: Double = 0.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Cover

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Title
                Authors
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // a fixed-width cover-shaped block, so the image fills it and the view hugs
    // the left margin instead of centring inside a square frame
    private var Cover: some View {
        Color.clear
            .aspectRatio(Layout.coverAspect, contentMode: .fit)
            .frame(width: Layout.coverWidth)
            .overlay {
                KFImage(cover)
                    .requestModifier(AnyModifier.referer(referer))
                    .resizable()
                    .placeholder { Placeholder }
                    .fade(duration: Layout.fadeDuration)
                    .scaledToFill()
            }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
            .tappable(action: onOpenCovers)
    }

    private var Placeholder: some View {
        Rectangle()
            .fill(.primary.opacity(Layout.placeholderOpacity))
            .shimmer()
    }

    private var Title: some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .contextMenu { TitleMenu }
            .tappable(action: onOpenTitles)
    }

    @ViewBuilder
    private var TitleMenu: some View {
        Button {
            UIPasteboard.general.string = title
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }
    }

    @ViewBuilder
    private var Authors: some View {
        if !authors.isEmpty {
            Text(authors.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

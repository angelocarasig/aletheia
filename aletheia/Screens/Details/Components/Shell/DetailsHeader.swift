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
    var onSearchAll: () -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        // a cover is fitted into this box rather than forced into one shape.
        // the height is a standard 11:16 cover at 160pt, so an ordinary cover
        // draws exactly as it always has; the wider bound is what lets a square
        // or landscape cover use the room it needs instead of being cropped
        static let coverWidth: CGFloat = 160
        static let coverAspect: CGFloat = 11 / 16
        static let coverMaxWidth: CGFloat = 200
        static var coverMaxHeight: CGFloat { coverWidth / coverAspect }
        static let fadeDuration: Double = 0.25
        static let placeholderOpacity: Double = 0.1
    }

    @State private var measured: CGSize = .zero
    // reset by the cover changing, or a new preferred cover inherits the old
    // one's failure and never gets its own attempt
    @State private var unavailable = false

    // the image's own ratio, fitted inside the box. until it reports a size this
    // is the standard cover shape, so the common case never reflows and the
    // skeleton it replaces is already the right shape
    private var coverFrame: CGSize {
        guard measured.width > 0, measured.height > 0 else {
            return CGSize(width: Layout.coverWidth, height: Layout.coverMaxHeight)
        }

        let scale = min(
            Layout.coverMaxWidth / measured.width,
            Layout.coverMaxHeight / measured.height
        )
        return CGSize(width: measured.width * scale, height: measured.height * scale)
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

    @ViewBuilder
    private var Cover: some View {
        if unavailable {
            Unavailable
        } else {
            Artwork
        }
    }

    private var Unavailable: some View {
        Placeholder
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: coverFrame.width, height: coverFrame.height)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
            .tappable(action: onOpenCovers)
    }

    private var Artwork: some View {
        KFImage(cover)
            .requestModifier(AnyModifier.referer(referer))
            // kingfisher reports the decoded size, which is ratio-true even when
            // a processor has downsampled it - the ratio is all this needs
            .onSuccess { measured = $0.image.size }
            .resizable()
            .placeholder { Placeholder }
            // without this a dead url shimmers forever - kingfisher keeps showing
            // the placeholder on failure, so "loading" and "will never load" drew
            // identically. the header is where that was most visible
            .onFailure { _ in unavailable = true }
            .fade(duration: Layout.fadeDuration)
            .scaledToFill()
            // a new preferred cover is a new identity, so it crossfades in over
            // the old one rather than swapping hard
            .id(cover)
            .transition(.opacity)
            .frame(width: coverFrame.width, height: coverFrame.height)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.settle, value: coverFrame)
            .animation(.settle, value: cover)
            .tappable(action: onOpenCovers)
            .onChange(of: cover) { unavailable = false }
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

        Button(action: onSearchAll) {
            Label("Search All Sources", systemImage: "magnifyingglass")
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

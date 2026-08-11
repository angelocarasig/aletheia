//
//  CoverImage.swift
//  aletheia
//
//  Created by Angelo Carasig on 11/8/2026.
//

import SwiftUI
import Kingfisher

// artwork with three states, not two. every call site in the app drew a
// shimmering placeholder while loading and left it there when the load FAILED -
// so a cover whose url is permanently gone shimmers forever, which says "still
// working" about something that will never finish. it read as a stuck app
// rather than a missing image, and it is the reason a 404 on one poster looked
// like a bug in the reader.
//
// the failed state is deliberately quiet: a glyph on the same fill the
// placeholder used. artwork that will not load is not an error the reader can
// act on - the series is still theirs, still readable, and the row still names
// it. what it must not do is imply work in progress
struct CoverImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    @Environment(\.dimensions) private var dimensions
    @State private var failed = false

    private enum Layout {
        static let fillOpacity = 0.1
        // sized against the frame it is given rather than fixed: this draws in
        // everything from a 36pt thumbnail to a full-bleed backdrop
        static let glyphScale: CGFloat = 0.28
        static let glyphCeiling: CGFloat = 28
    }

    var body: some View {
        // the url is the identity: a recycled cell handed a new one must drop
        // the previous failure or the second series inherits the first's blank
        Group {
            if let url, !failed {
                KFImage(url)
                    .resizable()
                    .placeholder { Fill.shimmer() }
                    .onFailure { _ in failed = true }
                    .fade(duration: 0.25)
                    .aspectRatio(contentMode: contentMode)
            } else {
                Unavailable
            }
        }
        .onChange(of: url) { failed = false }
    }

    private var Fill: some View {
        Rectangle().fill(.primary.opacity(Layout.fillOpacity))
    }

    private var Unavailable: some View {
        Fill.overlay {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)

                Image(systemName: "photo")
                    .font(.system(size: min(side * Layout.glyphScale, Layout.glyphCeiling)))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Previews

#Preview("Cover states") {
    HStack(spacing: 16) {
        VStack(spacing: 8) {
            CoverImage(url: nil)
                .frame(width: 100, height: 145)
                .clipShape(.rect(cornerRadius: 8))
            Text("No url").font(.caption2).foregroundStyle(.secondary)
        }

        VStack(spacing: 8) {
            // a host that does not resolve, so it fails rather than hanging
            CoverImage(url: URL(string: "https://example.invalid/missing.jpg"))
                .frame(width: 100, height: 145)
                .clipShape(.rect(cornerRadius: 8))
            Text("Failed").font(.caption2).foregroundStyle(.secondary)
        }

        VStack(spacing: 8) {
            CoverImage(url: nil)
                .frame(width: 44, height: 60)
                .clipShape(.rect(cornerRadius: 4))
            Text("Thumb").font(.caption2).foregroundStyle(.secondary)
        }
    }
    .padding(16)
    .background(.canvas)
}

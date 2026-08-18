//
//  CoverImage.swift
//  aletheia
//
//  Created by Angelo Carasig on 11/8/2026.
//

import Kingfisher
import SwiftUI

// a dead url used to leave the loading shimmer up forever, reading as a stuck
// app rather than a missing image - failed is tracked separately from loading
struct CoverImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    @Environment(\.dimensions) private var dimensions
    @State private var failed = false

    private enum Layout {
        static let fillOpacity = 0.1
        static let glyphScale: CGFloat = 0.28
        static let glyphCeiling: CGFloat = 28
    }

    var body: some View {
        // reset on url change - a recycled cell must drop the previous failure
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

//
//  DetailsSynopsis.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsSynopsis: View {
    let synopsis: String

    @Environment(\.dimensions) private var dimensions

    @State private var isExpanded: Bool = false
    @State private var isTruncated: Bool = false
    @State private var clippedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private enum Layout {
        static let collapsedLines = 6
        static let expand: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Synopsis

            if isTruncated || isExpanded {
                ExpandToggle(isExpanded: $isExpanded)
            }
        }
    }

    @ViewBuilder
    private var Synopsis: some View {
        if isTruncated || isExpanded {
            SynopsisText.tappable {
                withAnimation(Layout.expand) { isExpanded.toggle() }
            }
        } else {
            SynopsisText
        }
    }

    // truncation can't be read off Text directly - an unclipped copy is rendered
    // hidden behind the clipped one and the two heights compared
    private var SynopsisText: some View {
        Text(synopsis)
            .font(.subheadline)
            .foregroundStyle(.textPrimary)
            .lineLimit(isExpanded ? nil : Layout.collapsedLines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                clippedHeight = height
                if fullHeight > 0 { isTruncated = fullHeight > height }
            }
            .background {
                Text(synopsis)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        fullHeight = height
                        if clippedHeight > 0 { isTruncated = height > clippedHeight }
                    }
            }
    }
}

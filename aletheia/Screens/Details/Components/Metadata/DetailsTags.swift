//
//  DetailsTags.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsTags: View {
    let tags: [String]

    @Environment(\.dimensions) private var dimensions

    @State private var isExpanded: Bool = false

    private enum Layout {
        static let collapsedCount = 8
        static let expand: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            FlowLayout(spacing: dimensions.spacing.space8) {
                ForEach(visible, id: \.self) { tag in
                    Badge(text: tag, tone: .neutral, size: .compact)
                }
            }

            if tags.count > Layout.collapsedCount {
                ExpandToggle(isExpanded: $isExpanded)
            }
        }
    }

    private var visible: [String] {
        isExpanded ? tags : Array(tags.prefix(Layout.collapsedCount))
    }
}

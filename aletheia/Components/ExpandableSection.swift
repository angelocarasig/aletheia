//
//  ExpandableSection.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct ExpandableSection<Content: View>: View {
    @Environment(\.dimensions) private var dimensions

    let title: String
    var count: Int?
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        count: Int? = nil,
        isExpanded: Bool,
        toggle: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.isExpanded = isExpanded
        self.toggle = toggle
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)

                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.vertical, dimensions.spacing.space8)
            .contentShape(.rect)
            .tappable(action: toggle)

            if isExpanded {
                VStack(spacing: 0) {
                    content()
                }
                .transition(
                    .asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .push(from: .bottom).combined(with: .opacity)
                    ))
            }
        }
    }
}

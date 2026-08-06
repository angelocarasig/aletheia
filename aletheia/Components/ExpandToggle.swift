//
//  ExpandToggle.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct ExpandToggle: View {
    @Binding var isExpanded: Bool

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let expand: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space4) {
            Spacer()
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            Text(isExpanded ? "Show Less" : "Show More")
        }
        .font(.caption)
        .foregroundStyle(.brand)
        .contentShape(.rect)
        .tappable {
            withAnimation(Layout.expand) { isExpanded.toggle() }
        }
    }
}

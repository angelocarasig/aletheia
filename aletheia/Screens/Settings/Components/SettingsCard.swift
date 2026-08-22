//
//  SettingsCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026
//

import SwiftUI

struct SettingsCard: View {
    let title: String
    var systemImage: String? = nil
    // an installed source's own artwork, in place of an SF Symbol - takes
    // priority over systemImage when both are somehow given
    var icon: ImageResource? = nil
    let detail: String
    let action: () -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let glyphWidth: CGFloat = 28
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Glyph
                .frame(width: Layout.glyphWidth)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                // contentTransition, not .transition - the string changes in place, no
                // view is inserted or removed for a .transition to fire on
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.settle, value: detail)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
        .tappable(action: action)
    }

    @ViewBuilder
    private var Glyph: some View {
        if let icon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

//
//  BackupActionSlab.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

struct BackupActionSlab: View {
    let icon: String?
    let label: String
    var tinted: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let height: CGFloat = 64
    }

    private var glyph: String? {
        isLoading ? "progress.indicator" : icon
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.title2)
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isLoading && !reduceMotion)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }

            Text(label)
                .font(.headline)
        }
        .foregroundStyle(isLoading ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity)
        .frame(height: Layout.height)
        .glassEffect(
            tinted ? .regular.tint(Palette.brand.opacity(0.35)).interactive() : .regular,
            in: .rect(cornerRadius: dimensions.radius.radius20, style: .continuous)
        )
        .contentShape(.rect)
        .tappable(action: action)
        .disabled(isLoading)
    }
}

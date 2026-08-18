//
//  DetailsCadence.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import SwiftUI

struct DetailsCadence: View {
    let display: DetailsComposer.Cadence.State.Display
    var force: (glyph: String, action: () -> Void)?

    @Environment(\.dimensions) private var dimensions
    @State private var spinning = false

    private enum Layout {
        static let glyph: CGFloat = 13
        static let padding: CGFloat = 10
        static let fillOpacity: Double = 0.05
        static let buttonHit: CGFloat = 44
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: display.glyph)
                .font(.system(size: Layout.glyph, weight: .medium))
                .foregroundStyle(.muted)
                .frame(width: Layout.glyph)

            Text(display.label)
                .font(.subheadline)
                .foregroundStyle(.muted)

            if let value = display.value {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            if let force {
                Image(systemName: force.glyph)
                    .font(.system(size: Layout.glyph, weight: .semibold))
                    .foregroundStyle(.brand)
                    .symbolEffect(.rotate, value: spinning)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Layout.buttonHit, height: Layout.buttonHit)
                    .contentShape(.rect)
                    .tappable {
                        spinning.toggle()
                        force.action()
                    }
                    .accessibilityLabel("Estimate the next chapter")
            }
        }
        .frame(minHeight: Layout.buttonHit)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, Layout.padding)
        .padding(.vertical, force == nil ? Layout.padding : 0)
        .animation(.settle, value: display)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius8)
        )
        .accessibilityElement(children: .contain)
    }
}

//
//  DetailsCadence.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import SwiftUI

// when the next chapter is likely, or why that cannot be said. one line, two
// surfaces, one definition - the chapter header while there is a backlog, and
// the Continue capsule once the reader is caught up
//
// carried on the metadata card's fill rather than as loose text. drawn as bare
// muted type it sat at exactly the weight of the "37 chapters" label beneath it,
// so the eye grouped the two and the prediction read as a second count. a filled
// surface separates it without adding colour or weight, which is the budget a
// line below the section heading has
//
// NOT the Banner component, though it is the nearest neighbour. Banner is a fact
// plus the one thing that resolves it - glyph, sentence, chevron - and this has
// no resolution and needs a weighted value inline. its own header also states
// why it is solid rather than glass, and the same reasoning applies here
struct DetailsCadence: View {
    let display: DetailsComposer.Cadence.State.Display
    // nil where the arithmetic already produced a date. a control that cannot
    // change its own answer is worse than no control
    var force: (glyph: String, action: () -> Void)?

    @Environment(\.dimensions) private var dimensions
    @State private var spinning = false

    private enum Layout {
        static let glyph: CGFloat = 13
        // the metadata cells' own values, so the two read as one family
        static let padding: CGFloat = 10
        static let fillOpacity: Double = 0.05
        static let buttonHit: CGFloat = 44
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space8) {
            // the glyph separates the five states at a glance without colour,
            // which stays reserved - nothing in this line is an alert, and an
            // overdue series is the common case rather than a failure
            Image(systemName: display.glyph)
                .font(.system(size: Layout.glyph, weight: .medium))
                .foregroundStyle(.muted)
                .frame(width: Layout.glyph)

            Text(display.label)
                .font(.subheadline)
                .foregroundStyle(.muted)

            if let value = display.value {
                // the only part carrying primary colour. a date is the thing
                // being looked for, and weighting it is what separates a
                // statement from a label
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
                    // a 44pt target around a 13pt glyph, so the row keeps its
                    // height and the tap does not need aiming
                    .frame(width: Layout.buttonHit, height: Layout.buttonHit)
                    .contentShape(.rect)
                    .tappable {
                        spinning.toggle()
                        force.action()
                    }
                    // the only tappable thing here, so it is the only thing
                    // wearing the brand colour
                    .accessibilityLabel("Estimate the next chapter")
            }
        }
        // the row keeps its height whether or not the button is there
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
        // contain, not combine: the sentence and the button are two elements
        // now, and combining them would bury the only control on the row
        .accessibilityElement(children: .contain)
    }
}

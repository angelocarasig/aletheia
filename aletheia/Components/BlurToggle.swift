//
//  BlurToggle.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// whether what is on screen is covered - never whether it was fetched. the two
// questions get different glyphs, so "on" is never ambiguous between queried and
// visible. scattered dots rather than an eye: the eye asks whether you may look,
// this asks how much of the artwork is resolved. dense dots read as the noise
// that is actually on screen, sparse ones as it clearing
struct BlurToggle: View {
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // low against high, not low against medium - the middle glyph is
            // near enough to the sparse one that the swap read as a colour
            // change alone. aqi.low is the sparsest the family goes
            Image(systemName: isOn ? "aqi.low" : "aqi.high")
                .foregroundStyle(isOn ? AnyShapeStyle(.danger) : AnyShapeStyle(.muted))
        }
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Shown" : "Blurred")
    }
}

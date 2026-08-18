//
//  BlurToggle.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

struct BlurToggle: View {
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // aqi.low vs aqi.high, not aqi.medium - medium is close enough to
            // high that the swap would read as a colour change, not a shape change
            Image(systemName: isOn ? "aqi.low" : "aqi.high")
                .foregroundStyle(isOn ? AnyShapeStyle(.danger) : AnyShapeStyle(.muted))
        }
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Shown" : "Blurred")
    }
}

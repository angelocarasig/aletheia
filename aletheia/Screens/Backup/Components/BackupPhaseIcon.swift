//
//  BackupPhaseIcon.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// pass the same Namespace.ID across every phase of one screen so
// glassEffectID actually morphs between them; a fresh namespace per screen
struct BackupPhaseIcon: View {
    let systemImage: String?
    let tint: Color
    var tintOpacity: Double = 0.15
    var isSpinning: Bool = false
    var bounceTrigger: Bool = false
    let namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let iconSize: CGFloat = 36
        static let glassSize: CGFloat = 96
    }

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: Layout.iconSize))
                    .foregroundStyle(tint)
                    .symbolEffect(
                        .rotate, options: .repeat(.continuous),
                        isActive: isSpinning && !reduceMotion
                    )
                    .symbolEffect(.bounce, value: bounceTrigger)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .frame(width: Layout.glassSize, height: Layout.glassSize)
        .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: .circle)
        .glassEffectID("icon", in: namespace)
    }
}

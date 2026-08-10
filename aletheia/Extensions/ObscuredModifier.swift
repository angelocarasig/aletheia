//
//  ObscuredModifier.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

extension View {
    func obscured(_ isObscured: Bool) -> some View {
        modifier(ObscuredModifier(isObscured: isObscured))
    }
}

// the one treatment for covered artwork, so a card cannot disagree with another
// card about what covered looks like. applied to the artwork alone - our own
// annotations (badges, activity marks) sit above it and stay readable
struct ObscuredModifier: ViewModifier {
    let isObscured: Bool

    private enum Layout {
        // the artwork must not be legible through it, and a blurred cover still
        // has to read as a cover rather than as a failed load
        static let blurRadius: CGFloat = 24
        static let scrim: Double = 0.15
        static let duration: Double = 0.25
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: isObscured ? Layout.blurRadius : 0)
            .overlay {
                if isObscured {
                    Rectangle().fill(.black.opacity(Layout.scrim))
                }
            }
            .animation(.smooth(duration: Layout.duration), value: isObscured)
    }
}

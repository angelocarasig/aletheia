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

// applies to artwork alone - callers layer their own badges/activity marks
// on top, after this modifier, so those annotations stay readable
struct ObscuredModifier: ViewModifier {
    let isObscured: Bool

    private enum Layout {
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

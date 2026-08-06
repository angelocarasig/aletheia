//
//  TappableModifier.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

extension View {
    func tappable(action: @escaping () -> Void) -> some View {
        Button(action: action) { self }
            .buttonStyle(.pressable)
    }
}

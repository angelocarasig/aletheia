//
//  ShimmerModifier.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

extension View {
    @ViewBuilder
    func shimmer() -> some View {
        modifier(Shimmer())
    }
}

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isInitial = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.55)
        } else {
            content
                .mask(
                    // animation is on the gradient, not the masked content - it
                    // keeps replaying on isInitial for as long as the skeleton
                    // is on screen, including lazy cards mounting in later
                    LinearGradient(
                        colors: [.black.opacity(0.4), .black, .black.opacity(0.4)],
                        startPoint: isInitial ? .init(x: -0.3, y: -0.3) : .init(x: 1, y: 1),
                        endPoint: isInitial ? .init(x: 0, y: 0) : .init(x: 1.3, y: 1.3)
                    )
                    .animation(
                        .linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false),
                        value: isInitial)
                )
                .onAppear { isInitial = false }
        }
    }
}

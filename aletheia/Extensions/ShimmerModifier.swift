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
    @State private var isInitial = true

    func body(content: Content) -> some View {
        content
            .mask(
                LinearGradient(
                    colors: [.black.opacity(0.4), .black, .black.opacity(0.4)],
                    startPoint: isInitial ? .init(x: -0.3, y: -0.3) : .init(x: 1, y: 1),
                    endPoint: isInitial ? .init(x: 0, y: 0) : .init(x: 1.3, y: 1.3)
                )
            )
            .animation(.linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false), value: isInitial)
            .onAppear { isInitial = false }
    }
}

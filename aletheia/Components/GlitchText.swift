//
//  GlitchText.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import SwiftUI

// scrambles a locked collection's name in place, character by character, on
// a timer - a plain blur reads as "same content, hidden" but a name is text,
// not artwork, so this reads as "you don't have this decoded" instead
struct GlitchText: View {
    let text: String

    private enum Layout {
        static let interval: TimeInterval = 0.08
        // fraction of characters swapped each tick - not every character
        // every tick, or it reads as noise rather than a glitch
        static let swapFraction: Double = 0.35
        static let glyphs = Array("!@#$%^&*<>?/\\|~01234567890XYZ")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Layout.interval)) { _ in
            Text(scrambled)
                .monospaced()
        }
    }

    private var scrambled: String {
        String(
            text.map { character in
                guard !character.isWhitespace, Double.random(in: 0...1) < Layout.swapFraction
                else { return character }
                return Layout.glyphs.randomElement() ?? character
            })
    }
}

#Preview {
    VStack(spacing: 16) {
        GlitchText(text: "Private Collection")
            .font(.headline)
        GlitchText(text: "Favorites")
            .font(.subheadline)
    }
    .padding()
}

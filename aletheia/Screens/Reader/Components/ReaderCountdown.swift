//
//  ReaderCountdown.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// lives outside the overlay on purpose - chrome is hidden exactly when this matters
struct ReaderCountdown: View {
    let progress: Double

    private enum Layout {
        static let height: CGFloat = 3
        static let trackOpacity: Double = 0.2
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(Layout.trackOpacity))

                Capsule()
                    .fill(Palette.brand)
                    .frame(width: proxy.size.width * min(max(0, progress), 1))
            }
        }
        // engine already quantises what it publishes; animating on top only adds lag
        .frame(height: Layout.height)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

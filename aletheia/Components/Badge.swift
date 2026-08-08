//
//  Badge.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct Badge: View {
    private let label: Text
    private let tone: Palette.Tone

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        // a soft wash over the material rather than a solid fill: .subtle at full
        // strength reads too heavy against the page, so it rides a material that
        // carries most of the surface and lets the tint just colour it
        static let tint: Double = 0.5
        static let border: Double = 0.2
        static let stroke: CGFloat = 0.5
    }

    init(text: String, tone: Palette.Tone = .brand) {
        self.label = Text(text)
        self.tone = tone
    }

    // a literal keeps its inflection markup - passing the same string through a
    // String parameter renders the ^[…](inflect:) syntax verbatim
    init(_ key: LocalizedStringKey, tone: Palette.Tone = .brand) {
        self.label = Text(key)
        self.tone = tone
    }

    var body: some View {
        label
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(tone.text)
            .padding(.horizontal, dimensions.spacing.space12)
            .padding(.vertical, dimensions.spacing.space8)
            // material for glassy depth, a soft tone wash over it, and a hairline
            // tone edge so the pill has a defined shape against the backdrop
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(tone.subtle.opacity(Layout.tint))
                }
            }
            .overlay {
                Capsule().strokeBorder(tone.text.opacity(Layout.border), lineWidth: Layout.stroke)
            }
    }
}

extension Classification {
    var tone: Palette.Tone {
        switch self {
        case .Safe: .success
        case .Suggestive: .warning
        case .Explicit: .danger
        case .Unknown: .neutral
        }
    }
}

extension Publication {
    var tone: Palette.Tone {
        switch self {
        case .Ongoing: .brand
        case .Completed: .success
        case .Hiatus: .warning
        case .Cancelled: .danger
        case .Unknown: .neutral
        }
    }
}

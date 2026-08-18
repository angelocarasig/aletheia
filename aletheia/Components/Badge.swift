//
//  Badge.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct Badge: View {
    enum Size {
        case standalone
        case compact
    }

    private let label: Text
    private let tone: Palette.Tone
    private let size: Size

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let tint: Double = 0.5
        static let border: Double = 0.2
        static let stroke: CGFloat = 0.5
    }

    init(text: String, tone: Palette.Tone = .brand, size: Size = .standalone) {
        self.label = Text(text)
        self.tone = tone
        self.size = size
    }

    // a literal keeps its inflection markup - passing the same string through a
    // String parameter renders the ^[...](inflect:) syntax verbatim
    init(_ key: LocalizedStringKey, tone: Palette.Tone = .brand, size: Size = .standalone) {
        self.label = Text(key)
        self.tone = tone
        self.size = size
    }

    var body: some View {
        label
            .font(font)
            .fontWeight(.semibold)
            .foregroundStyle(tone.text)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
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

    private var font: Font {
        switch size {
        case .standalone: .subheadline
        case .compact: .caption2
        }
    }

    private var horizontal: CGFloat {
        switch size {
        case .standalone: dimensions.spacing.space12
        case .compact: dimensions.spacing.space8
        }
    }

    private var vertical: CGFloat {
        switch size {
        case .standalone: dimensions.spacing.space8
        case .compact: dimensions.spacing.space4
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

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
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(tone.text)
            .padding(.horizontal, dimensions.spacing.space8)
            .padding(.vertical, dimensions.spacing.space4)
            .background(tone.subtle, in: .capsule)
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

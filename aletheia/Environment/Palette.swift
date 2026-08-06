//
//  Palette.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import SwiftUI

// primitives (Radix 12-step scales, light/dark colorsets) live in
// Resources/Assets.xcassets/Colors/Radix. views never reference a raw step —
// only the semantic aliases below.
enum Palette {
    // brand (blue)
    static let brand = Color("blue9")
    static let brandHover = Color("blue10")
    static let brandSubtle = Color("blue3")
    static let brandBorder = Color("blue7")
    static let brandText = Color("blue11")
    static let onBrand = Color.white

    // danger (red)
    static let danger = Color("red9")
    static let dangerSubtle = Color("red3")
    static let dangerBorder = Color("red7")
    static let dangerText = Color("red11")

    // warning (amber)
    static let warning = Color("amber9")
    static let warningSubtle = Color("amber3")
    static let warningText = Color("amber11")

    // success (grass)
    static let success = Color("grass9")
    static let successSubtle = Color("grass3")
    static let successText = Color("grass11")

    // a semantic role, paired so text and its background always come from the
    // steps meant for them: 11 reads on 3, where step 9 is a solid fill and is
    // unreadable as text on anything pale
    enum Tone {
        case brand, success, warning, danger, neutral

        var text: Color {
            switch self {
            case .brand: Palette.brandText
            case .success: Palette.successText
            case .warning: Palette.warningText
            case .danger: Palette.dangerText
            case .neutral: Palette.muted
            }
        }

        var subtle: Color {
            switch self {
            case .brand: Palette.brandSubtle
            case .success: Palette.successSubtle
            case .warning: Palette.warningSubtle
            case .danger: Palette.dangerSubtle
            case .neutral: Palette.surface
            }
        }
    }

    // neutrals (system semantic — free dark mode, contrast, vibrancy)
    static let textPrimary = Color.primary
    static let muted = Color.secondary
    static let canvas = Color(.systemBackground)
    static let surface = Color(.secondarySystemBackground)
    static let border = Color(.separator)
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Palette.brand }
    static var brandHover: Color { Palette.brandHover }
    static var brandSubtle: Color { Palette.brandSubtle }
    static var brandBorder: Color { Palette.brandBorder }
    static var brandText: Color { Palette.brandText }
    static var onBrand: Color { Palette.onBrand }

    static var danger: Color { Palette.danger }
    static var dangerSubtle: Color { Palette.dangerSubtle }
    static var dangerBorder: Color { Palette.dangerBorder }
    static var dangerText: Color { Palette.dangerText }

    static var warning: Color { Palette.warning }
    static var warningSubtle: Color { Palette.warningSubtle }
    static var warningText: Color { Palette.warningText }

    static var success: Color { Palette.success }
    static var successSubtle: Color { Palette.successSubtle }
    static var successText: Color { Palette.successText }

    static var textPrimary: Color { Palette.textPrimary }
    static var muted: Color { Palette.muted }
    static var canvas: Color { Palette.canvas }
    static var surface: Color { Palette.surface }
    static var border: Color { Palette.border }
}

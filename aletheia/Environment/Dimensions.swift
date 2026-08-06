//
//  Dimensions.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import SwiftUI

private struct DimensionsKey: EnvironmentKey {
    static let defaultValue = Dimensions()
}

extension EnvironmentValues {
    var dimensions: Dimensions {
        get { self[DimensionsKey.self] }
        set { self[DimensionsKey.self] = newValue }
    }
}

struct Dimensions {
    enum Spacing {
        static let space2: CGFloat = 2
        static let space4: CGFloat = 4
        static let space8: CGFloat = 8
        static let space12: CGFloat = 12
        static let space16: CGFloat = 16
        static let space20: CGFloat = 20
        static let space24: CGFloat = 24
        static let space32: CGFloat = 32
        static let space40: CGFloat = 40
        static let space48: CGFloat = 48
        static let space64: CGFloat = 64
    }
    let spacing = (
        space2: Spacing.space2,
        space4: Spacing.space4,
        space8: Spacing.space8,
        space12: Spacing.space12,
        space16: Spacing.space16,
        space20: Spacing.space20,
        space24: Spacing.space24,
        space32: Spacing.space32,
        space40: Spacing.space40,
        space48: Spacing.space48,
        space64: Spacing.space64
    )

    enum Radius {
        static let radius4: CGFloat = 4
        static let radius8: CGFloat = 8
        static let radius12: CGFloat = 12
        static let radius16: CGFloat = 16
        static let radius20: CGFloat = 20
        static let radius28: CGFloat = 28
        static let capsule: CGFloat = .infinity
    }
    let radius = (
        radius4: Radius.radius4,
        radius8: Radius.radius8,
        radius12: Radius.radius12,
        radius16: Radius.radius16,
        radius20: Radius.radius20,
        radius28: Radius.radius28,
        capsule: Radius.capsule
    )

    enum Size {
        static let icon16: CGFloat = 16
        static let icon20: CGFloat = 20
        static let icon24: CGFloat = 24
        static let icon32: CGFloat = 32
        static let icon40: CGFloat = 40
        static let dot: CGFloat = 8
        static let control: CGFloat = 44
        static let controlL: CGFloat = 50
    }
    let size = (
        icon16: Size.icon16,
        icon20: Size.icon20,
        icon24: Size.icon24,
        icon32: Size.icon32,
        icon40: Size.icon40,
        dot: Size.dot,
        control: Size.control,
        controlL: Size.controlL
    )

    let screenMargin: CGFloat = Spacing.space16
    let touchTarget: CGFloat = 44
}

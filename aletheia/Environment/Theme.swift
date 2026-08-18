//
//  Theme.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import SwiftUI

struct Theme {
    static let `default` = Theme()
}

extension Animation {
    // scope is loading swaps only - staged sheets and expand/collapse
    // animations keep their own values deliberately
    static let settle: Animation = .smooth(duration: 0.35)
}

extension AnyTransition {
    // blur-replace scales and blurs, the two effects reduce motion asks to
    // remove - fade is the substitute the accessibility guidelines prescribe
    static func replace(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}

extension EnvironmentValues {
    @Entry var theme = Theme.default
}

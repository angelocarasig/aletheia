//
//  Theme.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import SwiftUI

struct Theme {
    // define tokens here: animations, transitions, etc.

    static let `default` = Theme()
}

extension Animation {
    // the one loading-swap animation: every skeleton -> content crossfade keys
    // on this, so surfaces cannot drift apart a duration at a time. smooth is
    // the no-bounce spring and the platform default; 0.35 sits mid-band of the
    // 200-400ms content-replacement consensus. scope is loading swaps - staged
    // sheets and expand/collapse animations keep their own values deliberately
    static let settle: Animation = .smooth(duration: 0.35)
}

extension AnyTransition {
    // blur-replace scales and blurs, the two effects reduce motion asks to
    // remove - so every use passes the flag and degrades to the fade, which is
    // the substitute the guidelines themselves prescribe
    static func replace(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}

extension EnvironmentValues {
    @Entry var theme = Theme.default
}

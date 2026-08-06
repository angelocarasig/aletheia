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

extension EnvironmentValues {
    @Entry var theme = Theme.default
}

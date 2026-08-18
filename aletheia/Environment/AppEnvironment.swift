//
//  AppEnvironment.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

// defaults exist only to satisfy @Entry - both are injected at the root once
// bootstrap finishes, so reading either without injection means a view is
// outside the bootstrapped tree
extension EnvironmentValues {
    @Entry var database: DatabaseClient = .client
    @Entry var compositor = Compositor(database: .client)
}

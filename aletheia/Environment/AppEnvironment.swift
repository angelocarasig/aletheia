//
//  AppEnvironment.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

// both are injected at the root once bootstrap finishes. the defaults exist only
// to satisfy @Entry - reading either without injection means a view is outside
// the bootstrapped tree, and standing the database up there is what we are trying
// to avoid
extension EnvironmentValues {
    @Entry var database: DatabaseClient = .client
    @Entry var compositor = Compositor(database: .client)
}

//
//  AppEnvironment.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var database: DatabaseClient = .client
    @Entry var compositor = Compositor()
}

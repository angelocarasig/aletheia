//
//  AuthCapturing.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

protocol AuthCapturing: Sendable {
    @MainActor func capture(for spec: AuthSpecification) async throws -> SourceCredential
}

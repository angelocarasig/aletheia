//
//  AuthSpecification.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

enum AuthRequirement: Sendable, Codable, Hashable {
    case cookie(name: String)
}

struct AuthSpecification: Sendable {
    let requirements: [AuthRequirement]
    let challengeURL: URL
    let userAgent: String?
    let maneuver: String
    let interactive: Bool
}

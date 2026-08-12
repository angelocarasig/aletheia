//
//  AuthSpecification.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

enum AuthRequirement: Sendable, Codable, Hashable {
    // optional means "carry it if the browser happened to earn one". a tenant
    // that is not currently challenging never mints cf_clearance, and requiring
    // it would poll to the timeout and fail a source that otherwise works
    case cookie(name: String, optional: Bool = false)

    // not everything a request needs is in the jar - a csrf token minted with the
    // session can be a meta tag, which only the document has
    case meta(name: String, header: String)
}

struct AuthSpecification: Sendable {
    let requirements: [AuthRequirement]
    let challengeURL: URL
    let userAgent: String?
    let maneuver: String
    let interactive: Bool
}

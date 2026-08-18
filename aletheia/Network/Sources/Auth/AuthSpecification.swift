//
//  AuthSpecification.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

enum AuthRequirement: Sendable, Codable, Hashable {
    // optional: a tenant not currently challenging never mints cf_clearance, and
    // requiring it would poll to the timeout and fail a source that otherwise works
    case cookie(name: String, optional: Bool = false)
    case meta(name: String, header: String)
}

struct AuthSpecification: Sendable {
    let requirements: [AuthRequirement]
    let challengeURL: URL
    let userAgent: String?
    let maneuver: String
    let interactive: Bool

    // a clearance is issued against the request that was refused, not a site root -
    // mangafire's root is an spa shell, so loading it instead of the actually
    // challenged endpoint (/api/titles) left the interstitial retrying to timeout.
    // challengeURL stays the fallback for a refresh with no request behind it
    // (a proactive expiry, or the sources screen)
    func targeting(_ url: URL?) -> AuthSpecification {
        guard let url, url.host() == challengeURL.host() else { return self }

        return AuthSpecification(
            requirements: requirements,
            challengeURL: url,
            userAgent: userAgent,
            maneuver: maneuver,
            interactive: interactive
        )
    }
}

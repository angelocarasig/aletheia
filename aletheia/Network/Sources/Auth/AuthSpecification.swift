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

    // a clearance is issued against the request that was refused, so the browser
    // has to ask for that request and not for a site root that was never the
    // thing in question. mangafire's root is an spa shell; what cloudflare
    // actually challenged was /api/titles, and loading the shell instead left
    // the interstitial retrying itself every ten seconds to the timeout.
    //
    // the declared challengeURL stays the fallback, for a refresh with no
    // request behind it - a proactive expiry, or the sources screen asking
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

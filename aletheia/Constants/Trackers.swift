//
//  Trackers.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

extension Constants {
    enum Trackers {
        // both are public clients, neither holds a secret: anilist has no PKCE
        // and issues the same token from either grant, so the implicit grant
        // is used; myanimelist must be registered as a public app type, since
        // `web` issues a secret and then demands it
        static let anilistClientId = "48245"
        static let malClientId = "0d027f8f881f16cf799509ba11ca4cf4"

        // distinct paths rather than a bare scheme, so a callback can never be
        // routed to the wrong handler
        static let scheme = "aletheia"
        static let anilistRedirect = "aletheia://anilist-auth"
        static let malRedirect = "aletheia://mal-auth"

        static let anilistAPI = URL(string: "https://graphql.anilist.co")!
        static let anilistAuthorize = URL(string: "https://anilist.co/api/v2/oauth/authorize")!

        static let malAPI = URL(string: "https://api.myanimelist.net/v2")!
        static let malAuthorize = URL(string: "https://myanimelist.net/v1/oauth2/authorize")!
        static let malToken = URL(string: "https://myanimelist.net/v1/oauth2/token")!

        // api.mangabaka.dev is dead and answers every request with a 500 carrying
        // a plain-english move notice, so a client checking only status codes
        // reads a permanent redirect as an outage
        static let mangaBakaAPI = URL(string: "https://api.mangabaka.org")!

        // mangabaka's token endpoint offers no public-client auth method and
        // nothing registers an application, so a pasted PAT is the supported
        // path. see docs/features/tracker-mangabaka.md §2
        static let mangaBakaSettings = URL(string: "https://mangabaka.org/u/settings")!

        // lets the paste field reject a wrong string before it costs a request
        static let mangaBakaTokenPrefix = "mb-"

        // 180/min on /my/*, six times anilist's real ceiling, is headroom, not
        // a limit - search is a separate, tighter bucket (30/min), a debounce
        // question on the link sheet rather than a pacing one here
        static let mangaBakaRequestsPerMinute = 120
        static let mangaBakaSearchRequestsPerMinute = 30

        // myanimelist 307s any user-agent containing tachiyomi or app.mihon to an
        // empty 204 through an undocumented substring blocklist. ours is checked
        // against it
        static let userAgent = "aletheia/1.0 (moe.aletheia)"

        // anilist is nominally 90/min but has been in a declared degraded state
        // at 30 for a long time - probed live and confirmed, budget against the
        // real one. myanimelist publishes nothing, has no 429, and answers a
        // burst with a 5-10 minute ban, so it is paced rather than budgeted
        static let anilistRequestsPerMinute = 25
        static let malRequestSpacing: Duration = .milliseconds(1000)
    }
}

//
//  Network.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

extension Constants {
    enum Network {
        static let userAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

        // how long a captured credential is trusted regardless of what its
        // cookie claims. measured, not guessed: see SourceCredential.isValid.
        // under the shortest observed median (11 minutes) so a refresh lands
        // before the wall does, and far enough over zero that a burst of
        // requests shares one capture
        static let credentialLifetime: TimeInterval = 10 * 60

        // how long a host may go silent before the request is dead. thirty is
        // chosen against BGContinuedProcessingTask, which expires a run whose
        // progress has not moved for about that long - a request outliving the
        // system's patience takes the whole run down with it
        static let timeout: TimeInterval = 30
        // the session's own timeout cannot be shortened per request, so a
        // ping enforces its own ceiling by racing it at the call site
        static let pingTimeout: Duration = .milliseconds(1500)

        // timeoutInterval measures silence, not total transfer time, so a host
        // trickling bytes never trips it - only reachable via session config,
        // which is why the service owns a session instead of using .shared
        static let resourceTimeout: TimeInterval = 120

        // half the sources here are cloudflare-fronted scrapes; reader page
        // prefetch runs outside this gate
        static let requestsPerHost = 3

        // mangaball serialises every request against one PHPSESSID on the php
        // session-file lock - concurrency there buys about 1.4x and pays in
        // tail latency, and a queue deeper than `timeout` fails as a bare
        // timeout that reads as the site being down
        static let requestsPerHostOverrides: [String: Int] = [
            "mangaball.net": 1
        ]

        // http/2 multiplexes, so this caps connections rather than requests
        // and cannot replace the gate above
        static let connectionsPerHost = 6
    }
}

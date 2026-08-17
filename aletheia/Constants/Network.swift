//
//  Network.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

extension Constants {
    enum Network {
        static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

        // how long a host may go silent before the request is dead. thirty is
        // chosen against BGContinuedProcessingTask, which expires a run whose
        // progress has not moved for about that long - a request outliving the
        // system's patience takes the whole run down with it
        // how long a captured credential is trusted regardless of what its
        // cookie claims. measured, not guessed: see SourceCredential.isValid.
        // under the shortest observed median (11 minutes) so a refresh lands
        // before the wall does, and far enough over zero that a burst of
        // requests shares one capture
        static let credentialLifetime: TimeInterval = 10 * 60

        static let timeout: TimeInterval = 30
        // a health check that takes as long as a real request tells you nothing
        // you could not have guessed. imposed by the caller racing it, since the
        // session's own timeout cannot be shortened per request
        static let pingTimeout: Duration = .milliseconds(1500)

        // the ceiling on a whole transfer, which timeoutInterval cannot express:
        // it measures silence, so a host trickling bytes never trips it. only
        // reachable through a session configuration, which is why the service
        // owns a session rather than using .shared
        static let resourceTimeout: TimeInterval = 120

        // requests in flight at one host. politeness is a property of the site,
        // not of our idea of a source: half the sources here are cloudflare-
        // fronted scrapes, and reader page prefetch runs outside this gate
        static let requestsPerHost = 3

        // hosts that want something other than the default. mangaball serialises
        // every request against one PHPSESSID on the php session-file lock, so
        // concurrency there buys about 1.4x and pays in tail latency - and a queue
        // deeper than `timeout` fails as a bare timeout, which reads as the site
        // being down. the lock is per session, and our model holds one per source
        static let requestsPerHostOverrides: [String: Int] = [
            "mangaball.net": 1
        ]

        // the OS-level floor beneath the gate. http/2 multiplexes, so this caps
        // connections rather than requests and cannot replace the gate
        static let connectionsPerHost = 6
    }
}

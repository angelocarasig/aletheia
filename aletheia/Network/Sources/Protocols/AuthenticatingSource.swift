//
//  AuthenticatingSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

// an opt-in for a source sitting behind a wall that a plain request cannot get
// through - a cloudflare interstitial, a login, anything needing cookies a
// browser earned. everyone else conforms to SourceService alone and talks to
// NetworkService directly.
//
// conforming buys the whole retry story: the requester serves a cached
// credential, refreshes proactively before it expires, notices a challenge that
// slipped through anyway, single-flights the refresh so ten concurrent requests
// wake one capture, and replays the request once. `specification` is what a
// capture has to collect for that to work - which cookies, whether the reader
// has to see the sheet.
//
// two things worth knowing before conforming:
//
// route every request through `fetch(_:)`. a call that reaches NetworkService
// directly gets no credential, no challenge detection and no retry, and it will
// work right up until the site decides to challenge.
//
// the user agent is the engine's own, read once at capture and pinned onto the
// credential. the one that earned the cookies is the one that must send them -
// cloudflare ties a clearance to the agent it was issued for. a hand-written
// string used to be pinned onto the page instead, which is the same invariant
// from the wrong end: the challenge fingerprints the real engine and compares,
// and a claim it could not back up failed the challenge outright. a source can
// still declare an agent if it genuinely needs a specific one
protocol AuthenticatingSource: SourceService {
    var specification: AuthSpecification { get }
    var requester: AuthRequester { get }
}

extension AuthenticatingSource {
    func fetch(_ url: URL, headers: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await requester.send(request, for: self)
        return data
    }

    // the default covers cloudflare, which is what almost every wall turns out
    // to be. a source fronted by something else overrides this - answering true
    // is what makes the requester capture again and replay, so a wall it cannot
    // recognise reads as an ordinary failure
    func isChallenge(response: HTTPURLResponse, body: Data) -> Bool {
        isCloudflareChallenge(response: response, body: body)
    }

    // named separately because an override cannot reach a protocol extension's
    // default the way a subclass reaches super: a source recognising its own wall
    // still wants cloudflare's markers underneath, and this is how it asks
    func isCloudflareChallenge(response: HTTPURLResponse, body: Data) -> Bool {
        if response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" {
            return true
        }

        if response.statusCode == 403 || response.statusCode == 503,
            response.value(forHTTPHeaderField: "Server")?.lowercased().contains("cloudflare")
                == true
        {
            return true
        }

        if let html = String(data: body, encoding: .utf8) {
            let markers = [
                "__cf_chl", "cf-browser-verification", "challenge-platform", "Just a moment",
            ]
            if markers.contains(where: html.contains) {
                return true
            }
        }

        return false
    }
}

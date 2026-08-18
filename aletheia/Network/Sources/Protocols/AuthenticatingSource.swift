//
//  AuthenticatingSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

// route every request through `fetch(_:)` - a call that reaches NetworkService
// directly gets no credential, no challenge detection and no retry, and will work
// right up until the site decides to challenge.
//
// the user agent is the engine's own, read once at capture and pinned onto the
// credential - the one that earned the cookies is the one that must send them,
// since cloudflare ties a clearance to the agent it was issued for
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

    // a source fronted by something else overrides this - answering true is what
    // makes the requester capture again and replay, so a wall it cannot recognise
    // reads as an ordinary failure instead
    func isChallenge(response: HTTPURLResponse, body: Data) -> Bool {
        isCloudflareChallenge(response: response, body: body)
    }

    // named separately since an override can't reach a protocol extension's default
    // the way a subclass reaches super - this is how it still gets at cloudflare's
    // markers underneath its own check
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

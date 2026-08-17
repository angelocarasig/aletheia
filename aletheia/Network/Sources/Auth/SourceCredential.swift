//
//  SourceCredential.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

struct SourceCredential: Sendable, Codable {
    let cookies: [String: String]
    // whatever a capture collected that is not a cookie - mangaball's csrf token
    // is a meta tag on the page that minted the session, and the pair is checked
    // together. optional so credentials saved before this field decode unchanged
    let headers: [String: String]?
    let userAgent: String
    let expiresAt: Date?
    // when we earned it, which is the only date here we can vouch for. optional
    // so credentials saved before this field decode unchanged
    let capturedDate: Date?

    init(
        cookies: [String: String],
        headers: [String: String]? = nil,
        userAgent: String,
        expiresAt: Date?,
        capturedDate: Date? = Date()
    ) {
        self.cookies = cookies
        self.headers = headers
        self.userAgent = userAgent
        self.expiresAt = expiresAt
        self.capturedDate = capturedDate
    }

    // the stated expiry is a hint, not a contract - `docs/features/source-auth.md`
    // said so before there was evidence, and there is evidence now. every
    // cf_clearance this app has ever captured declares 365 days; measured across
    // 56 credentials on a device, the median time before the wall refused one was
    // 11 minutes for toonily, 14 for mangafire, 87 for mangaball. trusting the
    // stated date meant the proactive half of this design never once fired: of
    // 236 refreshes in that log, 226 were a request failing and 10 were an expiry.
    //
    // so a credential is also stale once it is older than we are willing to
    // vouch for, whatever the cookie claims. this does not add refreshes - the
    // wall was forcing them at this rate anyway - it moves them off the path of a
    // request the reader is waiting on
    func isValid(skew: TimeInterval = 60) -> Bool {
        if let capturedDate,
           Date().timeIntervalSince(capturedDate) > Constants.Network.credentialLifetime {
            return false
        }

        guard let expiresAt else { return true }
        return Date() < expiresAt.addingTimeInterval(-skew)
    }

    func apply(to request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        for (key, value) in headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if !cookies.isEmpty {
            let cookieHeader = cookies
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
            // merged, not overwritten: a source may set request-scoped cookies of
            // its own (toonily-mature rides only gate-open queries) and they must
            // survive the credential landing on top
            let merged = [request.value(forHTTPHeaderField: "Cookie"), cookieHeader]
                .compactMap { $0 }
                .joined(separator: "; ")
            request.setValue(merged, forHTTPHeaderField: "Cookie")
        }
    }
}

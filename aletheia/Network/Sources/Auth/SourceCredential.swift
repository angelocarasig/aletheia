//
//  SourceCredential.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

struct SourceCredential: Sendable, Codable {
    let cookies: [String: String]
    // non-cookie capture output, e.g. mangaball's csrf token from a meta tag;
    // optional so credentials saved before this field was added still decode
    let headers: [String: String]?
    let userAgent: String
    let expiresAt: Date?
    // the only date here we can vouch for (see isValid); optional so credentials
    // saved before this field was added still decode
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

    // the stated expiry is a hint, not a contract: every captured cf_clearance
    // declares 365 days, but measured across 56 credentials the wall refused them
    // after a median of 11 min (toonily), 14 min (mangafire), 87 min (mangaball) -
    // of 236 logged refreshes, 226 were a failed request and only 10 were an
    // actual expiry. so staleness is capped at credentialLifetime regardless of
    // what expiresAt claims
    func isValid(skew: TimeInterval = 60) -> Bool {
        if let capturedDate,
            Date().timeIntervalSince(capturedDate) > Constants.Network.credentialLifetime
        {
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
            let cookieHeader =
                cookies
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
            // merged, not overwritten: toonily-mature sets a request-scoped cookie
            // of its own that must survive the credential landing on top
            let merged = [request.value(forHTTPHeaderField: "Cookie"), cookieHeader]
                .compactMap { $0 }
                .joined(separator: "; ")
            request.setValue(merged, forHTTPHeaderField: "Cookie")
        }
    }
}

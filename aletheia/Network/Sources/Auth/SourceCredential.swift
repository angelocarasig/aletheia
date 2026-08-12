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

    init(cookies: [String: String], headers: [String: String]? = nil, userAgent: String, expiresAt: Date?) {
        self.cookies = cookies
        self.headers = headers
        self.userAgent = userAgent
        self.expiresAt = expiresAt
    }

    func isValid(skew: TimeInterval = 60) -> Bool {
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

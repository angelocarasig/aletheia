//
//  SourceCredential.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

struct SourceCredential: Sendable, Codable {
    let cookies: [String: String]
    let userAgent: String
    let expiresAt: Date?

    func isValid(skew: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return true }
        return Date() < expiresAt.addingTimeInterval(-skew)
    }

    func apply(to request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

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

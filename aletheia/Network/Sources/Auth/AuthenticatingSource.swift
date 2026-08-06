//
//  AuthenticatingSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

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

    func isChallenge(response: HTTPURLResponse, body: Data) -> Bool {
        if response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" {
            return true
        }

        if response.statusCode == 403 || response.statusCode == 503,
           response.value(forHTTPHeaderField: "Server")?.lowercased().contains("cloudflare") == true {
            return true
        }

        if let html = String(data: body, encoding: .utf8) {
            let markers = ["__cf_chl", "cf-browser-verification", "challenge-platform", "Just a moment"]
            if markers.contains(where: html.contains) {
                return true
            }
        }

        return false
    }
}

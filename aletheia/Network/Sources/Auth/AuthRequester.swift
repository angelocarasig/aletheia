//
//  AuthRequester.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

actor AuthRequester {
    private let network: NetworkConfiguration
    private let capturer: any AuthCapturing
    private let log: AppLog
    private var refreshTasks: [String: Task<SourceCredential, Error>] = [:]
    private var lastRefresh: [String: Date] = [:]

    // long enough that a screenful of rows shares one answer, short enough that a
    // reader retrying by hand a moment later gets a real attempt
    private static let refreshCooldown: TimeInterval = 30

    init(network: NetworkConfiguration, capturer: any AuthCapturing, log: AppLog) {
        self.network = network
        self.capturer = capturer
        self.log = log
    }

    func credential(for source: any AuthenticatingSource, targeting url: URL? = nil) async throws
        -> SourceCredential
    {
        let slug = source.descriptor.slug

        if let cached = try? Keychain.sources.load(SourceCredential.self, account: slug),
            cached.isValid()
        {
            return cached
        }

        log.log("[\(slug)] no valid cached credential - refreshing", category: "auth")
        return try await refresh(for: source, targeting: url)
    }

    func forceRefresh(for source: any AuthenticatingSource) async throws -> SourceCredential {
        try await refresh(for: source)
    }

    func peek(slug: String) -> SourceCredential? {
        try? Keychain.sources.load(SourceCredential.self, account: slug)
    }

    func send(_ request: URLRequest, for source: any AuthenticatingSource) async throws -> (
        Data, HTTPURLResponse
    ) {
        var authed = request
        let credential = try await credential(for: source, targeting: request.url)
        credential.apply(to: &authed)

        let (data, response) = try await network.send(authed)

        guard source.isChallenge(response: response, body: data) else {
            return (data, response)
        }

        // a credential minted seconds ago and refused is the wall saying no, not
        // an expiry - recapturing immediately produces the same cookies and the
        // same refusal. previously stampeded 5 preset rows into 4 verification
        // sheets in 30s, so a repeat within cooldown returns as an ordinary
        // failure instead (see below)
        let slug = source.descriptor.slug
        // names only, never values - the credential is secret, the log is not
        log.log(
            "[\(slug)] challenged \(request.url?.path() ?? "/") - sent \(describe(authed))",
            category: "auth")

        if let last = lastRefresh[slug], Date().timeIntervalSince(last) < Self.refreshCooldown {
            log.log(
                "[\(slug)] challenge persists after a recent refresh - not capturing again",
                category: "auth")
            return (data, response)
        }

        log.log("[\(slug)] challenge detected - refreshing then retrying once", category: "auth")
        let fresh = try await refresh(for: source, targeting: request.url)
        var retry = request
        fresh.apply(to: &retry)
        return try await network.send(retry)
    }

    private func describe(_ request: URLRequest) -> String {
        let headers = request.allHTTPHeaderFields ?? [:]
        let cookies = (headers["Cookie"] ?? "")
            .split(separator: ";")
            .compactMap { $0.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) }
            .sorted()
        let ambient = request.url.flatMap { HTTPCookieStorage.shared.cookies(for: $0) } ?? []

        return "headers [\(headers.keys.sorted().joined(separator: ", "))]"
            + ", cookie [\(cookies.joined(separator: ", "))]"
            + ", shared jar [\(ambient.map(\.name).sorted().joined(separator: ", "))]"
    }

    private func refresh(for source: any AuthenticatingSource, targeting url: URL? = nil)
        async throws -> SourceCredential
    {
        let slug = source.descriptor.slug

        if let existing = refreshTasks[slug] {
            log.log("[\(slug)] joining in-flight refresh (single-flight)", category: "auth")
            return try await existing.value
        }

        let specification = source.specification.targeting(url)
        let task = Task<SourceCredential, Error> { [capturer] in
            try await capturer.capture(for: specification)
        }
        refreshTasks[slug] = task
        // lastRefresh is stamped regardless of outcome - the cooldown above must
        // apply to a failed capture too, not just a successful one
        defer {
            refreshTasks[slug] = nil
            lastRefresh[slug] = Date()
        }

        let credential = try await task.value

        do {
            try Keychain.sources.save(credential, account: slug)
            log.log("[\(slug)] credential saved to keychain", category: "auth")
        } catch {
            log.log("[\(slug)] keychain save FAILED - \(error)", level: .error, category: "auth")
            throw error
        }

        return credential
    }
}

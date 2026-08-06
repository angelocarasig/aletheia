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

    init(network: NetworkConfiguration, capturer: any AuthCapturing, log: AppLog) {
        self.network = network
        self.capturer = capturer
        self.log = log
    }

    func credential(for source: any AuthenticatingSource) async throws -> SourceCredential {
        let slug = source.descriptor.slug

        // deliberately silent. this is the steady state and fires once per
        // request, which buried everything worth reading under five identical
        // lines at a time. the refresh below is the state change worth logging
        if let cached = try? Keychain.sources.load(SourceCredential.self, account: slug), cached.isValid() {
            return cached
        }

        log.log("[\(slug)] no valid cached credential — refreshing", category: "auth")
        return try await refresh(for: source)
    }

    func forceRefresh(for source: any AuthenticatingSource) async throws -> SourceCredential {
        try await refresh(for: source)
    }

    func peek(slug: String) -> SourceCredential? {
        try? Keychain.sources.load(SourceCredential.self, account: slug)
    }

    func send(_ request: URLRequest, for source: any AuthenticatingSource) async throws -> (Data, HTTPURLResponse) {
        var authed = request
        let credential = try await credential(for: source)
        credential.apply(to: &authed)

        let (data, response) = try await network.send(authed)

        guard source.isChallenge(response: response, body: data) else {
            return (data, response)
        }

        log.log("[\(source.descriptor.slug)] challenge detected — refreshing then retrying once", category: "auth")
        let fresh = try await refresh(for: source)
        var retry = request
        fresh.apply(to: &retry)
        return try await network.send(retry)
    }

    private func refresh(for source: any AuthenticatingSource) async throws -> SourceCredential {
        let slug = source.descriptor.slug

        if let existing = refreshTasks[slug] {
            log.log("[\(slug)] joining in-flight refresh (single-flight)", category: "auth")
            return try await existing.value
        }

        let specification = source.specification
        let task = Task<SourceCredential, Error> { [capturer] in
            try await capturer.capture(for: specification)
        }
        refreshTasks[slug] = task
        defer { refreshTasks[slug] = nil }

        let credential = try await task.value

        do {
            try Keychain.sources.save(credential, account: slug)
            log.log("[\(slug)] credential saved to keychain", category: "auth")
        } catch {
            log.log("[\(slug)] keychain save FAILED — \(error)", category: "auth")
            throw error
        }

        return credential
    }
}

//
//  TrackerAuthority.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// who is signed in, and the only thing that reads or writes the tracker keychain.
// a sibling of AuthRequester, not a generalisation of it - that one drives a
// headless browser and detects expiry from a challenge page; here expiry is a
// status code and a refresh is one form post. see docs/features/trackers.md §6
actor TrackerAuthority {
    private let network: NetworkConfiguration
    private let services: [Tracker: any TrackerService]
    private let log: AppLog

    private var refreshTasks: [Tracker: Task<TrackerCredential, Error>] = [:]

    init(
        network: NetworkConfiguration, services: [Tracker: any TrackerService],
        log: AppLog = .shared
    ) {
        self.network = network
        self.services = services
        self.log = log
    }

    // MARK: Reading

    // no refresh, no network. the settings screen and every offline render go
    // through this, so a locked device reports nothing rather than throwing
    nonisolated func peek(_ tracker: Tracker) -> TrackerCredential? {
        try? Keychain.trackers.load(TrackerCredential.self, account: tracker.rawValue)
    }

    nonisolated func accounts() -> [Tracker: TrackerCredential] {
        Dictionary(
            uniqueKeysWithValues: Tracker.allCases.compactMap { tracker in
                peek(tracker).map { (tracker, $0) }
            })
    }

    func token(for tracker: Tracker) async throws -> String {
        guard let credential = peek(tracker) else { throw TrackerError.signedOut }
        guard !credential.isValid() else { return credential.accessToken }

        guard !credential.needsReauthentication else {
            // anilist's year is up, or myanimelist's refresh token was refused -
            // every request from here fails until they sign in again
            log.log(
                "[\(tracker.rawValue)] token expired with no refresh - reauthentication required",
                level: .warning, category: "trackers")
            throw TrackerError.reauthenticationRequired
        }

        return try await refresh(tracker).accessToken
    }

    // one refresh, then the caller retries once - a service with nothing to
    // refresh with goes straight to asking the reader
    func recover(_ tracker: Tracker) async throws -> String {
        guard let credential = peek(tracker), credential.isRefreshable else {
            throw TrackerError.reauthenticationRequired
        }
        return try await refresh(tracker).accessToken
    }

    // reads the keychain only, so it answers the same on the first launch after
    // the token died as it did the moment it died
    nonisolated func needsReauthentication(_ tracker: Tracker) -> Bool {
        peek(tracker)?.needsReauthentication ?? false
    }

    // MARK: Signing in

    // everything one attempt needs, handed back to complete() rather than held
    // here: two sign-ins racing would otherwise clobber each other's verifier,
    // which is the bug the previous attempt shipped
    struct Authorization: Sendable {
        let tracker: Tracker
        let url: URL
        let state: String
        let verifier: String
    }

    nonisolated func authorization(for tracker: Tracker) throws -> Authorization {
        // a pasted-token service has no browser round trip to open. stated
        // rather than left to a default, because reaching here at all means a
        // screen asked the wrong question for this service
        guard !tracker.usesPastedToken else { throw TrackerError.signedOut }

        let state = Self.entropy()
        let verifier = Self.entropy()

        var components: URLComponents
        switch tracker {
        case .mangaBaka:
            // excluded by the guard above; restated because the compiler cannot
            // see that usesPastedToken names exactly this case
            throw TrackerError.signedOut

        case .anilist:
            guard !Constants.Trackers.anilistClientId.isEmpty else {
                throw TrackerError.notConfigured
            }
            components = URLComponents(
                url: Constants.Trackers.anilistAuthorize, resolvingAgainstBaseURL: false)!
            // exactly two parameters, and adding a third breaks the flow: the
            // redirect comes from the application's own settings rather than the
            // request, and sending redirect_uri or state anyway comes back as
            // unsupported_grant_type after the login round trip. verified
            // against the endpoint 2026-08-10.
            //
            // implicit, so the token arrives in the fragment and there is
            // nothing to exchange - no secret ships in the binary
            components.queryItems = [
                .init(name: "client_id", value: Constants.Trackers.anilistClientId),
                .init(name: "response_type", value: "token"),
            ]
            // no state to compare, so nothing pretends to. what stands in for it
            // is the session itself: ASWebAuthenticationSession only resolves
            // for the callback of the request it opened, so a response cannot
            // arrive from anywhere else the way a web redirect can
            return Authorization(
                tracker: tracker, url: components.url ?? Constants.Trackers.anilistAuthorize,
                state: "", verifier: verifier)

        case .myAnimeList:
            guard !Constants.Trackers.malClientId.isEmpty else { throw TrackerError.notConfigured }
            components = URLComponents(
                url: Constants.Trackers.malAuthorize, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                .init(name: "response_type", value: "code"),
                .init(name: "client_id", value: Constants.Trackers.malClientId),
                .init(name: "redirect_uri", value: Constants.Trackers.malRedirect),
                .init(name: "state", value: state),
                // required here, unlike the rfc, and `plain` is the only method
                // myanimelist accepts - S256 is rejected outright
                .init(name: "code_challenge", value: verifier),
                .init(name: "code_challenge_method", value: "plain"),
            ]
        }

        guard let url = components.url else { throw TrackerError.unavailable }
        return Authorization(tracker: tracker, url: url, state: state, verifier: verifier)
    }

    func complete(_ callback: URL, with authorization: Authorization) async throws
        -> TrackerCredential
    {
        let tracker = authorization.tracker
        let parameters = Self.parameters(from: callback)

        if let error = parameters["error"] {
            throw TrackerError.rejected(parameters["error_description"] ?? error)
        }

        // the csrf defence, and under myanimelist's forced plain PKCE it is the
        // only thing binding the response to our request. anilist's implicit
        // grant accepts no state at all, so there it is empty and there is
        // nothing to check
        if !authorization.state.isEmpty {
            guard parameters["state"] == authorization.state else {
                throw TrackerError.rejected("The sign-in response did not match the request.")
            }
        }

        let token: String
        var refreshToken: String?
        var expiresDate: Date?

        switch tracker {
        case .mangaBaka:
            // unreachable: authorization(for:) refuses to build a url for it, so
            // no callback can name it
            throw TrackerError.signedOut

        case .anilist:
            guard let accessToken = parameters["access_token"] else {
                throw TrackerError.rejected("No token was returned.")
            }
            token = accessToken
            // a year, and there is no refresh - re-authenticating is the flow.
            // the fragment carries expires_in alongside the token (undocumented,
            // but three shipping clients depend on it); the jwt's own exp is the
            // fallback, so a nil expiry is not a state this can reach
            expiresDate =
                parameters["expires_in"]
                .flatMap(TimeInterval.init)
                .map { Date().addingTimeInterval($0) }
                ?? TrackerCredential.expiry(inJWT: accessToken)

        case .myAnimeList:
            guard let code = parameters["code"] else {
                throw TrackerError.rejected("No authorization code was returned.")
            }
            let response = try await exchange(
                fields: [
                    "client_id": Constants.Trackers.malClientId,
                    "code": code,
                    "code_verifier": authorization.verifier,
                    "grant_type": "authorization_code",
                    "redirect_uri": Constants.Trackers.malRedirect,
                ]
            )
            token = response.accessToken
            refreshToken = response.refreshToken
            expiresDate = response.expiresDate
        }

        guard let service = services[tracker] else { throw TrackerError.unavailable }
        let viewer = try await service.viewer(token: token)

        let credential = TrackerCredential(
            accessToken: token,
            refreshToken: refreshToken,
            expiresDate: expiresDate,
            username: viewer.name,
            avatar: viewer.avatar,
            scoreFormat: tracker.fixedScoreFormat ?? viewer.scoreFormat
        )

        try store(credential, for: tracker)
        log.log("[\(tracker.rawValue)] signed in as \(viewer.name)", category: "trackers")
        return credential
    }

    // no callback, no code to exchange - the token the reader pastes is the
    // credential. validated before it is stored, unlike the redirect flows: a
    // string typed or pasted by hand is evidence of nothing until something asks,
    // and that round trip also fills in the account name and score scale
    func signIn(token pasted: String, for tracker: Tracker) async throws -> TrackerCredential {
        let token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TrackerError.rejected("Paste your token to continue.") }
        guard let service = services[tracker] else { throw TrackerError.unavailable }

        let viewer = try await service.viewer(token: token)

        let credential = TrackerCredential(
            accessToken: token,
            // nothing to rotate, and no declared expiry anywhere in the spec: the
            // token lives until the reader revokes it. isValid() then answers true
            // forever, which is correct here and would be mihon's synthesised
            // expiry bug on a service that does expire
            refreshToken: nil,
            expiresDate: nil,
            username: viewer.name,
            avatar: viewer.avatar,
            scoreFormat: tracker.fixedScoreFormat ?? viewer.scoreFormat
        )

        try store(credential, for: tracker)
        log.log("[\(tracker.rawValue)] signed in as \(viewer.name)", category: "trackers")
        return credential
    }

    func signOut(_ tracker: Tracker) {
        refreshTasks[tracker]?.cancel()
        refreshTasks[tracker] = nil
        Keychain.trackers.delete(account: tracker.rawValue)
        log.log("[\(tracker.rawValue)] signed out", category: "trackers")
    }

    // MARK: Refresh

    private func refresh(_ tracker: Tracker) async throws -> TrackerCredential {
        if let existing = refreshTasks[tracker] {
            // myanimelist rotates its refresh token, so two concurrent refreshes
            // invalidate each other and the loser is signed out for no reason
            log.log(
                "[\(tracker.rawValue)] joining in-flight refresh (single-flight)",
                category: "trackers")
            return try await existing.value
        }

        guard let credential = peek(tracker), let refreshToken = credential.refreshToken else {
            throw TrackerError.reauthenticationRequired
        }

        let task = Task<TrackerCredential, Error> { [weak self] in
            guard let self else { throw TrackerError.unavailable }
            return try await self.perform(refresh: refreshToken, for: tracker, on: credential)
        }
        refreshTasks[tracker] = task
        defer { refreshTasks[tracker] = nil }

        return try await task.value
    }

    private func perform(
        refresh refreshToken: String,
        for tracker: Tracker,
        on credential: TrackerCredential
    ) async throws -> TrackerCredential {
        // only myanimelist has a refresh token to spend; anilist's year simply
        // runs out. an unreachable case, stated rather than assumed, because the
        // alternative is posting one service's client id to the other's endpoint
        guard tracker == .myAnimeList else { throw TrackerError.reauthenticationRequired }

        let response: TokenResponse
        do {
            response = try await exchange(
                fields: [
                    "client_id": Constants.Trackers.malClientId,
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                ]
            )
        } catch TrackerError.reauthenticationRequired {
            // dropping the refresh token (not the whole credential) closes the
            // dead-token-spent-on-every-push loop without losing the evidence that
            // the account was ever connected. needsReauthentication then answers
            // true - the same signature anilist's expiry produces, so one
            // predicate covers both services and survives a relaunch
            var stranded = credential
            stranded.refreshToken = nil
            stranded.expiresDate = .distantPast
            try? store(stranded, for: tracker)
            log.log(
                "[\(tracker.rawValue)] refresh token rejected - reauthentication required",
                level: .error, category: "trackers")
            throw TrackerError.reauthenticationRequired
        }

        var updated = credential
        updated.accessToken = response.accessToken
        // rotated on every refresh, and the old one dies the moment this lands
        updated.refreshToken = response.refreshToken ?? refreshToken
        updated.expiresDate = response.expiresDate
        updated.issuedDate = .now

        try store(updated, for: tracker)
        log.log("[\(tracker.rawValue)] token refreshed", category: "trackers")
        return updated
    }

    // saving has to throw rather than fail quietly: a credential returned but
    // never stored leaves an account signed in until the next launch and then
    // silently signed out
    private func store(_ credential: TrackerCredential, for tracker: Tracker) throws {
        do {
            try Keychain.trackers.save(credential, account: tracker.rawValue)
        } catch {
            log.log(
                "[\(tracker.rawValue)] keychain save FAILED - \(error)", level: .error,
                category: "trackers")
            throw error
        }
    }

    // MARK: Token endpoint

    private struct TokenResponse: Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresDate: Date?
    }

    private struct TokenPayload: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: TimeInterval?
    }

    // hand-encoded, because the token endpoint takes form fields and nothing
    // else. it also sits behind a WAF that occasionally answers a post with
    // captcha html, so a decode failure is not necessarily our bug
    private func exchange(fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Constants.Trackers.malToken)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Constants.Trackers.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Self.form(fields).data(using: .utf8)

        let (data, response) = try await network.send(request)

        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 400 {
                throw TrackerError.reauthenticationRequired
            }
            throw TrackerError.rejected("Sign-in failed (\(response.statusCode)).")
        }

        guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else {
            throw TrackerError.rejected("The sign-in response could not be read.")
        }

        return TokenResponse(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresDate: payload.expires_in.map { Date().addingTimeInterval($0) }
                ?? TrackerCredential.expiry(inJWT: payload.access_token)
        )
    }

    // MARK: Helpers

    private static func form(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        return
            fields
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }

    // one grant returns its answer in the query and the other in the fragment,
    // so both halves are read and the fragment wins where they collide
    private static func parameters(from url: URL) -> [String: String] {
        var found: [String: String] = [:]

        func absorb(_ query: String?) {
            guard let query else { return }
            var components = URLComponents()
            components.percentEncodedQuery = query
            for item in components.queryItems ?? [] where item.value != nil {
                found[item.name] = item.value
            }
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        absorb(components?.percentEncodedQuery)
        absorb(components?.percentEncodedFragment)
        return found
    }

    private static func entropy() -> String {
        let raw = UUID().uuidString + UUID().uuidString
        return raw.replacingOccurrences(of: "-", with: "")
    }
}

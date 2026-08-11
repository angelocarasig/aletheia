//
//  WebAuthCapturer.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import WebKit
import Observation

enum CaptureFailure: DescribableError {
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .timedOut: "Verification Timed Out"
        case .cancelled: "Verification Cancelled"
        }
    }

    var failureReason: String? {
        switch self {
        case .timedOut: "The source's checks didn't finish in time. Try again in a moment."
        // what happened, not the rule it broke: this case is only ever reached
        // by the reader closing the sheet themselves, and Try Again reopens it
        case .cancelled: "You closed the verification before it finished."
        }
    }
}

@MainActor
final class WebAuthCapturer: NSObject, AuthCapturing {
    private let presenter: AuthPresenter
    private let log: AppLog

    private var continuation: CheckedContinuation<SourceCredential, Error>?
    private var dataStore: WKWebsiteDataStore?
    private var page: WebPage?
    private var specification: AuthSpecification?
    private var userAgent = Constants.Network.userAgent
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var presented = false

    nonisolated init(presenter: AuthPresenter, log: AppLog) {
        self.presenter = presenter
        self.log = log
        super.init()
    }

    func capture(for specification: AuthSpecification) async throws -> SourceCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.specification = specification
            begin(specification)
        }
    }

    private func begin(_ specification: AuthSpecification) {
        let dataStore = WKWebsiteDataStore.default()
        self.dataStore = dataStore
        dataStore.httpCookieStore.add(self)

        let userAgent = specification.userAgent ?? Constants.Network.userAgent
        self.userAgent = userAgent

        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        let page = WebPage(configuration: configuration)
        page.customUserAgent = userAgent
        self.page = page

        page.load(URLRequest(url: specification.challengeURL))

        if specification.interactive {
            presented = true
            log.log("presenting auth sheet - \(specification.challengeURL.absoluteString)", category: "auth")
            presenter.show(page: page, maneuver: specification.maneuver) { [weak self] in
                self?.fail(.cancelled)
            }
        }

        startPolling(dataStore.httpCookieStore)
        trackNavigation()

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.fail(.timedOut)
        }
    }

    private func startPolling(_ cookieStore: WKHTTPCookieStore) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var delay: Duration = .milliseconds(500)
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, self.continuation != nil else { return }
                await self.evaluate(cookieStore)
                delay = min(delay * 2, .seconds(8))
            }
        }
    }

    private func trackNavigation() {
        guard let page else { return }
        withObservationTracking {
            _ = page.url
            _ = page.isLoading
        } onChange: {
            Task { @MainActor [weak self] in
                self?.handleNavigation()
            }
        }
    }

    private func handleNavigation() {
        guard continuation != nil, let cookieStore = dataStore?.httpCookieStore else { return }
        startPolling(cookieStore)
        trackNavigation()
    }

    private func evaluate(_ cookieStore: WKHTTPCookieStore) async {
        guard continuation != nil, let specification else { return }

        let requiredNames: [String] = specification.requirements.map {
            switch $0 { case .cookie(let name): name }
        }
        guard !requiredNames.isEmpty else { return }

        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }

        var captured: [String: String] = [:]
        var expiries: [Date] = []
        for name in requiredNames {
            guard let cookie = cookies.first(where: { $0.name == name }) else { return }
            captured[name] = cookie.value
            if let expiry = cookie.expiresDate { expiries.append(expiry) }
        }

        log.log("captured \(captured.count) cookie(s)", category: "auth")

        finish(.success(SourceCredential(
            cookies: captured,
            userAgent: userAgent,
            expiresAt: expiries.min()
        )))
    }

    private func fail(_ error: CaptureFailure) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<SourceCredential, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pollTask?.cancel()
        pollTask = nil
        dataStore?.httpCookieStore.remove(self)
        if presented {
            presented = false
            presenter.hide()
        }
        page = nil
        dataStore = nil
        continuation.resume(with: result)
    }
}

extension WebAuthCapturer: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { [weak self] in
            await self?.evaluate(cookieStore)
        }
    }
}

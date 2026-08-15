//
//  WebAuthCapturer.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import WebKit
import UIKit
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

        // interactive is a fact about the source; whether anyone is there to be
        // interactive with is a fact about the moment. a scheduled refresh runs
        // with the screen off, where a sheet presents to nobody, cannot be
        // completed, and would sit until the timeout burning runtime the rest of
        // the library needed. the headless half still runs - the poll and the
        // navigation tracking are what usually satisfy the challenge anyway - so
        // this loses the fallback, not the capture
        if specification.interactive && UIApplication.shared.applicationState == .active {
            presented = true
            log.log("presenting auth sheet - \(specification.challengeURL.absoluteString)", category: "auth")
            presenter.show(page: page, maneuver: specification.maneuver) { [weak self] in
                self?.fail(.cancelled)
            }
        } else if specification.interactive {
            log.log(
                "auth sheet suppressed - nobody is watching, capturing headlessly",
                category: "auth"
            )
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
        let host = specification.challengeURL.host() ?? ""

        var required: [String] = []
        var optional: [String] = []
        var metas: [(name: String, header: String)] = []
        for requirement in specification.requirements {
            switch requirement {
            case let .cookie(name, isOptional):
                if isOptional { optional.append(name) } else { required.append(name) }
            case let .meta(name, header):
                metas.append((name, header))
            }
        }
        guard !required.isEmpty || !metas.isEmpty else { return }

        let jar = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }

        // every source shares one data store, and cf_clearance is the name three
        // of them ask for - so matching on name alone hands whichever site was
        // visited last to whichever site is asking. mangafire's capture finished
        // in two seconds holding toonily's clearance, which is a cookie the
        // requester then replayed, the renderer then injected, and cloudflare
        // then refused, correctly, for a day
        let cookies = jar.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix(".\(domain)")
        }

        var captured: [String: String] = [:]
        var expiries: [Date] = []
        for name in required {
            guard let cookie = cookies.first(where: { $0.name == name }) else { return }
            captured[name] = cookie.value
            if let expiry = cookie.expiresDate { expiries.append(expiry) }
        }
        // taken if the browser earned one, never waited on
        for name in optional {
            guard let cookie = cookies.first(where: { $0.name == name }) else { continue }
            captured[name] = cookie.value
            if let expiry = cookie.expiresDate { expiries.append(expiry) }
        }

        var headers: [String: String] = [:]
        for meta in metas {
            guard let value = await content(ofMeta: meta.name), !value.isEmpty else { return }
            headers[meta.header] = value
        }

        // names, not a count. a wall that refuses a credential we believe we
        // captured is either a cookie we did not ask for or a cookie that was
        // never minted, and a count cannot tell those apart - so the line says
        // what we took and what was sitting in the jar beside it
        log.log(
            "captured [\(captured.keys.sorted().joined(separator: ", "))] + \(headers.count) header(s) from \(host) - jar held [\(jar.map { "\($0.name)@\($0.domain)" }.sorted().joined(separator: ", "))]",
            category: "auth"
        )

        finish(.success(SourceCredential(
            cookies: captured,
            headers: headers.isEmpty ? nil : headers,
            userAgent: userAgent,
            expiresAt: expiries.min()
        )))
    }

    // an interstitial has no such tag, so a missing value is "not there yet" and
    // the poll comes back - same shape as a cookie that has not been set
    private func content(ofMeta name: String) async -> String? {
        guard let page else { return nil }
        let script = "return document.querySelector('meta[name=\"' + name + '\"]')?.getAttribute('content') ?? null"
        let result = try? await page.callJavaScript(script, arguments: ["name": name], contentWorld: .page)
        return result as? String
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

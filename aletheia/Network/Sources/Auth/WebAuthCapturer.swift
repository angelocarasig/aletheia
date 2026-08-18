//
//  WebAuthCapturer.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import Observation
import UIKit
import WebKit

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
    private var sawWidget = false
    private var suppressed = false
    private var holding = false
    private var startedAt: ContinuousClock.Instant?

    // measured on device: a mangafire capture stalls, this fires, the sheet goes
    // up and the challenge completes ~6s later - 21s total. shortened from 15s
    // once logs showed it firing every time rather than never
    private static let stallSeconds = 4

    // hosts that have proved they need a visible page (mangafire), so the stall
    // wait isn't repeated on every capture. learned rather than declared since
    // it's a fact about a tenant's current configuration, which changes under us
    private static var demanding: Set<String> = []

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
        sawWidget = false
        suppressed = false
        holding = false
        startedAt = ContinuousClock.now

        let wants = specification.requirements.map { requirement in
            switch requirement {
            case .cookie(let name, let isOptional): isOptional ? "\(name)?" : name
            case .meta(let name, let header): "\(name)->\(header)"
            }
        }
        let url = specification.challengeURL
        let target = (url.host() ?? "?") + (url.path().isEmpty ? "/" : url.path())
        log.log(
            "capture started - \(target), wants [\(wants.joined(separator: ", "))]",
            category: "auth"
        )

        // per-capture store holding nothing, not the shared .default() store -
        // that one was persistent, so a stale clearance was still in it and got
        // handed back as a "fresh" capture within a few hundred ms, before the
        // page even finished loading: saved, replayed, refused, "recaptured",
        // refused again, forever, without webkit ever running the real challenge.
        // also ends a cross-site cf_clearance collision between sources.
        //
        // tradeoff: WKHTTPCookieStoreObserver does not fire on a non-persistent
        // store, so the poll (not the observer) is what actually carries this
        let dataStore = WKWebsiteDataStore.nonPersistent()
        self.dataStore = dataStore
        dataStore.httpCookieStore.add(self)

        // read back from the engine after load, not hand-written - cloudflare
        // pins to whichever agent earned the cookies, so this has to match exactly
        self.userAgent = specification.userAgent ?? Constants.Network.userAgent

        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        let page = WebPage(configuration: configuration)
        if let declared = specification.userAgent {
            page.customUserAgent = declared
        }
        self.page = page

        presenter.mount(page)
        page.load(URLRequest(url: specification.challengeURL))

        // mounted, not presented - a managed challenge that resolves itself in js
        // used to put a sheet in front of a reader with nothing to do; escalate()
        // is what raises the sheet once there's actually a job for a person
        startPolling(dataStore.httpCookieStore)
        trackNavigation()

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.fail(.timedOut)
        }
    }

    // still needed despite the per-capture store: a single challenge sets
    // cookies on more than one domain, and only one of them is the site
    private func matches(host: String, cookie: HTTPCookie) -> Bool {
        let domain =
            cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        return host == domain || host.hasSuffix(".\(domain)")
    }

    private func startPolling(_ cookieStore: WKHTTPCookieStore) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var delay: Duration = .milliseconds(250)
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, self.continuation != nil else { return }
                await self.evaluate(cookieStore)
                await self.escalate()
                delay = min(delay * 2, .seconds(4))
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
            case .cookie(let name, let isOptional):
                if isOptional { optional.append(name) } else { required.append(name) }
            case .meta(let name, let header):
                metas.append((name, header))
            }
        }
        guard !required.isEmpty || !metas.isEmpty else { return }

        // a cookie of the right name appearing is not the same as being through:
        // cloudflare sets the clearance partway along, and finishing there once
        // reported success in 579ms having never loaded a real page - the
        // clearance handed back was refused on every replay. so the test is the
        // one mihon uses: succeed only once the document is no longer the
        // interstitial
        if await isChallengeDocument() {
            if !holding {
                holding = true
                log.log("holding - still on the challenge document at \(elapsed)", category: "auth")
            }
            return
        }

        let jar = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }

        // matching on name alone once handed mangafire toonily's clearance
        // (three sources all ask for cf_clearance) - it replayed, was injected,
        // and cloudflare correctly refused it for a day
        let cookies = jar.filter { matches(host: host, cookie: $0) }

        var captured: [String: String] = [:]
        var expiries: [Date] = []
        for name in required {
            guard let cookie = cookies.first(where: { $0.name == name }) else { return }
            captured[name] = cookie.value
            if let expiry = cookie.expiresDate { expiries.append(expiry) }
        }
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

        let taken = captured.keys.sorted().map { name -> String in
            guard let expiry = cookies.first(where: { $0.name == name })?.expiresDate else {
                return name
            }
            return "\(name) (\(Int(expiry.timeIntervalSinceNow / 60))m)"
        }
        log.log(
            "captured [\(taken.joined(separator: ", "))] + \(headers.count) header(s) from \(host) - jar held [\(jar.map { "\($0.name)@\($0.domain)" }.sorted().joined(separator: ", "))]",
            category: "auth"
        )

        finish(
            .success(
                SourceCredential(
                    cookies: captured,
                    headers: headers.isEmpty ? nil : headers,
                    userAgent: await liveUserAgent(),
                    expiresAt: expiries.min(),
                    capturedDate: Date()
                )))
    }

    private func liveUserAgent() async -> String {
        guard let page else { return userAgent }
        let result = try? await page.callJavaScript(
            "return navigator.userAgent", contentWorld: .page)
        guard let live = result as? String, !live.isEmpty else { return userAgent }

        if live != userAgent {
            log.log("pinning engine agent - \(live)", category: "auth")
        }
        return live
    }

    // positive detection only: an unreachable page, a js error, or anything
    // unrecognised reads as "not a challenge" and falls back to the cookie test,
    // rather than an ambiguous read turning into a source that never captures
    private func isChallengeDocument() async -> Bool {
        guard let page else { return false }
        let script = """
            if (window._cf_chl_opt !== undefined) { return true }
            if (document.title.trim() === 'Just a moment...') { return true }
            return document.body?.textContent?.includes('Ray ID is') === true
            """
        let result = try? await page.callJavaScript(script, contentWorld: .page)
        return result as? Bool ?? false
    }

    private func content(ofMeta name: String) async -> String? {
        guard let page else { return nil }
        let script =
            "return document.querySelector('meta[name=\"' + name + '\"]')?.getAttribute('content') ?? null"
        let result = try? await page.callJavaScript(
            script, arguments: ["name": name], contentWorld: .page)
        return result as? String
    }

    // interactive is a fact about the source; applicationState == .active is a
    // fact about the moment - a scheduled refresh runs with the screen off, where
    // a sheet presents to nobody and sits until the timeout burning runtime
    private func escalate() async {
        guard !presented,
            continuation != nil,
            let page,
            let specification, specification.interactive,
            let reason = await escalation()
        else { return }

        guard UIApplication.shared.applicationState == .active else {
            if !suppressed {
                suppressed = true
                log.log("sheet suppressed - nobody is watching, still capturing", category: "auth")
            }
            return
        }

        presented = true
        log.log("presenting auth sheet - \(reason)", category: "auth")
        presenter.show(page: page, maneuver: specification.maneuver) { [weak self] in
            self?.fail(.cancelled)
        }
    }

    // two escalation paths: a widget on screen (the common case), or - since
    // whether a mounted page is actually visible isn't something this code can
    // check - a challenge that has stalled without settling, as insurance
    // against a source silently breaking instead
    private func escalation() async -> String? {
        if await isAwaitingHuman() {
            if !sawWidget {
                sawWidget = true
                log.log("interactive widget detected at \(elapsed)", category: "auth")
            }
            return "widget on screen"
        }

        if holding, let host = specification?.challengeURL.host(), Self.demanding.contains(host) {
            return "this wall has needed a visible page before"
        }

        guard holding, let startedAt,
            ContinuousClock.now - startedAt > .seconds(Self.stallSeconds)
        else { return nil }

        if let host = specification?.challengeURL.host() {
            Self.demanding.insert(host)
        }
        return "challenge has not settled in \(Self.stallSeconds)s"
    }

    // turnstile's checkbox renders inside a challenges.cloudflare.com iframe,
    // cross-origin from the document we can query - so its markup is out of
    // reach and the iframe's box size is the tell instead: the mode that wants a
    // tap paints ~300x65, while managed/invisible modes mount the same iframe at
    // zero size and solve themselves. the selector is a same-origin fallback for
    // a wall that isn't turnstile at all
    private func isAwaitingHuman() async -> Bool {
        guard let page else { return false }
        let script = """
            const visible = (element) => {
                const box = element.getBoundingClientRect()
                return box.width > 4 && box.height > 4
            }
            const frames = document.querySelectorAll('iframe[src*="challenges.cloudflare.com"]')
            if (Array.from(frames).some(visible)) { return true }
            const box = document.querySelector('input[type="checkbox"][aria-label*="Verify you are human" i]')
            return box !== null && visible(box)
            """
        let result = try? await page.callJavaScript(script, contentWorld: .page)
        return result as? Bool ?? false
    }

    private func fail(_ error: CaptureFailure) {
        finish(.failure(error))
    }

    private var elapsed: String {
        guard let startedAt else { return "?" }
        return "\((ContinuousClock.now - startedAt).milliseconds)ms"
    }

    private func finish(_ result: Result<SourceCredential, Error>) {
        guard let continuation else { return }

        let (outcome, level): (String, AppLog.Level) =
            switch result {
            case .success: ("captured", .info)
            case .failure(let error): ("FAILED - \(error)", .error)
            }
        log.log(
            "capture \(outcome) in \(elapsed) - widget \(sawWidget ? "seen" : "never seen"), sheet \(presented ? "shown" : "never shown"), challenge \(holding ? "was served" : "never seen")",
            level: level,
            category: "auth"
        )

        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pollTask?.cancel()
        pollTask = nil
        dataStore?.httpCookieStore.remove(self)
        presenter.unmount()
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

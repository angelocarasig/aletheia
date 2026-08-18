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
    private var sawWidget = false
    private var suppressed = false
    private var holding = false
    private var startedAt: ContinuousClock.Instant?

    // the mounted overlay is not enough for every wall. measured on device: a
    // mangafire capture stalls, this fires, the sheet goes up and the challenge
    // completes about six seconds later - 21s in total, of which this was the
    // dead part. shortened from 15s once the logs showed it firing every time
    // rather than never
    private static let stallSeconds = 4

    // which hosts have proved they need a visible page. the overlay satisfies
    // toonily and mangaball, which log "challenge never seen" and capture in a
    // few seconds; mangafire it does not satisfy, and waiting the stall out
    // again on every capture is a pause we already know the answer to. learned
    // rather than declared, because it is a fact about a tenant's current
    // configuration and those change under us
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

        // a store of its own, per capture, holding nothing. the shared .default()
        // store was persistent, so a clearance minted days ago was still in it -
        // and evaluate reads the jar rather than the navigation, so it handed
        // that one back as a fresh capture within a few hundred ms, before the
        // page had even finished loading. a clearance cloudflare had long since
        // stopped honouring was then saved, replayed, refused, "recaptured" and
        // refused again, forever, while webkit was never once allowed to run the
        // challenge that would have minted a real one.
        //
        // starting empty is what makes provenance a property of the design
        // rather than something to check: the only cookies in here are the ones
        // this navigation earned. it also ends the cross-site collision three
        // sources asking for cf_clearance used to have, and stops adult-source
        // cookies persisting in the shared store.
        //
        // the cost is that WKHTTPCookieStoreObserver does not fire on a
        // non-persistent store. the poll was always the workhorse and is what
        // carries this now; the observer stays registered because it costs one
        // line and nothing depends on it firing
        let dataStore = WKWebsiteDataStore.nonPersistent()
        self.dataStore = dataStore
        dataStore.httpCookieStore.add(self)

        // the engine's own agent, read back after the load and pinned onto the
        // credential. a hand-written string is a claim the engine then has to
        // back up, and this way there is nothing to back up. tested against
        // mangafire's loop 2026-08-16 and it changed nothing there, so it is not
        // a fix for anything - it is just the honest direction for the invariant
        // that does matter, which is that the agent earning the cookies is the
        // agent replaying them. a source needing a specific string still declares one
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

        // mounted, not presented. a managed challenge fires on any js-running
        // load and satisfies itself in a second or two, so a sheet up front sat
        // in front of a reader who had nothing to do in it, once per expiry, on
        // a source that was never asking them anything. the sheet is now what
        // escalate() raises when there is genuinely a person's job to do
        startPolling(dataStore.httpCookieStore)
        trackNavigation()

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.fail(.timedOut)
        }
    }

    // a cookie is only ours if its domain covers the host we loaded. the store
    // is per-capture now, so this is no longer the only thing standing between
    // three sources and each other's cf_clearance - but the challenge itself
    // sets cookies on more than one domain, and only one of them is the site
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

        // a cookie of the right name appearing is not the same as being through.
        // cloudflare sets the clearance partway along, and finishing there nils
        // the page and cancels the navigation that was about to prove it - the
        // capture reported success in 579ms having never loaded a real page, and
        // the clearance it handed back was refused on every replay. so the test
        // is the one mihon uses: succeed when the document is no longer the
        // interstitial, which means the wall has already served real content
        // against this clearance
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

        // every source shares one data store, and cf_clearance is the name three
        // of them ask for - so matching on name alone hands whichever site was
        // visited last to whichever site is asking. mangafire's capture finished
        // in two seconds holding toonily's clearance, which is a cookie the
        // requester then replayed, the renderer then injected, and cloudflare
        // then refused, correctly, for a day
        let cookies = jar.filter { matches(host: host, cookie: $0) }

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

        // names and lifetimes, not a count. a wall that refuses a credential we
        // believe we captured is either a cookie we did not ask for, a cookie
        // that was never minted, or one minted with a lifetime far shorter than
        // the reader is being told - and a count tells none of those apart
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

    // what the engine says it is, which is the only agent cloudflare will accept
    // the cookies back from. the declared fallback covers a page that cannot be
    // reached for an answer
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

    // positive detection only, and false whenever the answer is not clearly yes.
    // three sources already capture through this path, and a document we cannot
    // read must not become a source that never captures - so an unreachable page,
    // a js error, or anything unrecognised reads as "not a challenge" and lets
    // the cookie test decide, exactly as it did before
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

    // an interstitial has no such tag, so a missing value is "not there yet" and
    // the poll comes back - same shape as a cookie that has not been set
    private func content(ofMeta name: String) async -> String? {
        guard let page else { return nil }
        let script =
            "return document.querySelector('meta[name=\"' + name + '\"]')?.getAttribute('content') ?? null"
        let result = try? await page.callJavaScript(
            script, arguments: ["name": name], contentWorld: .page)
        return result as? String
    }

    // interactive is a fact about the source; whether anyone is there to be
    // interactive with is a fact about the moment. a scheduled refresh runs with
    // the screen off, where a sheet presents to nobody, cannot be completed, and
    // would sit until the timeout burning runtime the rest of the library needed
    private func escalate() async {
        guard !presented,
            continuation != nil,
            let page,
            let specification, specification.interactive,
            let reason = await escalation()
        else { return }

        // logged once: the poll keeps probing, and a backgrounded capture would
        // otherwise repeat this line every tick until the timeout
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

    // two ways a capture earns a sheet. the first is the one worth having: a
    // widget is on screen and somebody has to tick it.
    //
    // the second is insurance against the reason this whole mechanism exists. a
    // mounted page is only unthrottled while nothing covers it, and that is a
    // property of the view tree rather than of anything checked here - so a
    // challenge that has not settled long after it should have is treated as a
    // page that is not really visible, and the sheet is what makes it visible
    // beyond doubt. costs a sheet nobody needed in the worst case, against a
    // source that silently stops working in the other direction
    private func escalation() async -> String? {
        if await isAwaitingHuman() {
            if !sawWidget {
                sawWidget = true
                log.log("interactive widget detected at \(elapsed)", category: "auth")
            }
            return "widget on screen"
        }

        // a host that stalled before is presented the moment its challenge shows
        // rather than after the same wait a second time
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

    // the checkbox turnstile renders is inside a challenges.cloudflare.com
    // iframe, cross-origin from the document we can query - so its markup is out
    // of reach and the iframe's own box is the tell instead. the mode that wants
    // a tap paints a widget around 300x65; managed and invisible modes mount the
    // same iframe at zero size and solve themselves. the selector below is the
    // same-origin fallback for a wall that is not turnstile at all
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

        // the one line that says how a capture actually went. a timeout logs
        // nothing else at all, and "never saw a widget" versus "saw one and the
        // reader never finished it" are two entirely different problems
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

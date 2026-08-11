//
//  WebRenderer.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import WebKit

enum RenderError: DescribableError {
    case noContent

    var errorDescription: String? { "Nothing Came Back" }
    var failureReason: String? { "The server responded but returned nothing to read." }
}

extension WebRenderer {
    static let blank = URL(string: "about:blank")!
}

@MainActor
final class WebRenderer {
    private let log: AppLog

    nonisolated init(log: AppLog) {
        self.log = log
    }

    func sniff(
        _ url: URL,
        credential: SourceCredential,
        matching pattern: String,
        timeout: Duration = .seconds(20),
        attempts: Int = 3
    ) async throws -> String {
        for attempt in 1...max(1, attempts) {
            let session = await Session(url: url, credential: credential, capturing: pattern)
            if let body = try await Capture.wait(from: session.bridge, timeout: timeout) {
                log.log("sniffed \(pattern) (\(body.count) bytes)", category: "render")
                return body
            }
            log.log("sniff timed out for \(pattern) (attempt \(attempt)/\(attempts))", category: "render")
        }
        throw RenderError.noContent
    }

    func sniffPaged(
        _ url: URL,
        credential: SourceCredential,
        matching pattern: String,
        advancing nextSelector: String,
        maxPages: Int = 20,
        timeout: Duration = .seconds(20)
    ) async throws -> [String] {
        let session = await Session(url: url, credential: credential, capturing: pattern)
        let bridge = session.bridge

        var bodies: [String] = []
        guard let first = try await Capture.wait(from: bridge, timeout: timeout) else {
            log.log("sniffPaged: no response for \(pattern)", category: "render")
            return bodies
        }
        bodies.append(first)

        while bodies.count < maxPages {
            guard try await bridge.bool("return !!document.querySelector(sel)", ["sel": nextSelector]) else { break }
            try await bridge.call("document.querySelector(sel)?.click(); return null", ["sel": nextSelector])
            guard let body = try await Capture.wait(from: bridge, timeout: .seconds(8)) else { break }
            bodies.append(body)
        }

        log.log("sniffPaged \(pattern): \(bodies.count) page(s)", category: "render")
        return bodies
    }

    // paginates by clicking a DOM pager and returns each page's outerHTML, for
    // sources whose data exists only in the rendered DOM
    func renderPaged(
        _ url: URL,
        credential: SourceCredential,
        waitingFor selector: String,
        advancing nextSelector: String,
        trackingFirst rowSelector: String,
        maxPages: Int = 30,
        timeout: Duration = .seconds(20)
    ) async throws -> [String] {
        let session = await Session(url: url, credential: credential, capturing: "__dom__")
        let bridge = session.bridge

        var pages: [String] = []
        guard let first = try await waitRendered(bridge, selector: selector, timeout: timeout) else {
            log.log("renderPaged: \(selector) never appeared", category: "render")
            return pages
        }
        pages.append(first)

        while pages.count < maxPages {
            guard try await advance(bridge, next: nextSelector, tracking: rowSelector) else { break }
            if let html = try await outerHTML(bridge) { pages.append(html) }
        }

        log.log("renderPaged \(selector): \(pages.count) page(s)", category: "render")
        return pages
    }

    // runs one async JS function in the page and returns whatever string it
    // resolves to. the script owns its own waiting and paging, so a whole
    // multi-page harvest costs one round trip instead of one per step
    func run(
        _ url: URL,
        credential: SourceCredential,
        installing preload: String? = nil,
        seeding storage: [String: String] = [:],
        waitingFor selector: String? = nil,
        script: String,
        arguments: [String: Any] = [:],
        timeout: Duration = .seconds(60)
    ) async throws -> String {
        let clock = ContinuousClock()
        let started = clock.now
        log.log("run: opening \(url.absoluteString)", category: "render")

        let session = await Session(
            url: url,
            credential: credential,
            capturing: "__run__",
            preload: preload,
            storage: storage
        )
        let built = clock.now
        // the script's result is only reachable while the page is - releasing it
        // mid-call destroys the completion handler (WKErrorDomain 4). every other
        // method here touches the page in a loop and never notices; this one
        // calls it once, so ARC is free to let go the moment the call suspends
        defer { withExtendedLifetime(session) {} }

        guard try await session.ready(anchor: selector, within: timeout) else {
            log.log("run: \(selector ?? "document") never settled", category: "render")
            throw RenderError.noContent
        }
        let settled = clock.now

        let json = try await bounded(session, script: script, arguments: arguments, timeout: timeout)

        // split three ways because they fail for different reasons: build is
        // process launch, settle is the site booting, script is the work itself
        log.log(
            "run: build \(Self.ms(built - started))ms · settle \(Self.ms(settled - built))ms · script \(Self.ms(clock.now - settled))ms · \(json.count) bytes",
            category: "render"
        )
        return json
    }

    // callJavaScript has no timeout of its own, and discarding the page does not
    // reliably resume a pending call - WebKit drops the handler outright when the
    // content process is torn down, stranding the await forever. so the timeout
    // has to win the race rather than be trusted to unstick the loser
    private func bounded(
        _ session: Session,
        script: String,
        arguments: [String: Any],
        timeout: Duration
    ) async throws -> String {
        enum Outcome: Sendable {
            case answered(String?)
            case overran
        }

        let (stream, continuation) = AsyncStream<Outcome>.makeStream()

        let work = Task { @MainActor in
            let json = try? await session.bridge.string(script, arguments)
            continuation.yield(.answered(json))
        }
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            continuation.yield(.overran)
        }
        defer {
            work.cancel()
            watchdog.cancel()
        }

        var outcomes = stream.makeAsyncIterator()
        switch await outcomes.next() {
        case .answered(let json?):
            return json

        case .overran:
            log.log("run: script overran \(timeout), abandoning the page", category: "render")
            // best effort - the stuck call may never notice, but a fresh session
            // is cheaper than a wedged one held open
            session.discard()
            throw RenderError.noContent

        case .answered(nil), nil:
            throw RenderError.noContent
        }
    }

    private static func ms(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private func waitRendered(_ bridge: Bridge, selector: String, timeout: Duration) async throws -> String? {
        var waited: Duration = .zero
        var delay: Duration = .milliseconds(300)
        while waited < timeout {
            if try await bridge.bool("return !!document.querySelector(sel)", ["sel": selector]) {
                return try await outerHTML(bridge)
            }
            try await Task.sleep(for: delay)
            waited += delay
            delay = min(delay * 2, .seconds(1))
        }
        return nil
    }

    private func advance(_ bridge: Bridge, next: String, tracking rowSelector: String, timeout: Duration = .seconds(8)) async throws -> Bool {
        guard try await bridge.bool("return !!document.querySelector(sel)", ["sel": next]) else { return false }

        let before = try await firstHref(bridge, rowSelector)
        try await bridge.call("document.querySelector(sel)?.click(); return null", ["sel": next])

        var waited: Duration = .zero
        var delay: Duration = .milliseconds(200)
        while waited < timeout {
            try await Task.sleep(for: delay)
            waited += delay
            let now = try await firstHref(bridge, rowSelector)
            if now != nil, now != before { return true }
            delay = min(delay * 2, .milliseconds(800))
        }
        return false
    }

    private func outerHTML(_ bridge: Bridge) async throws -> String? {
        try await bridge.string("return document.documentElement.outerHTML")
    }

    private func firstHref(_ bridge: Bridge, _ selector: String) async throws -> String? {
        try await bridge.string("let e = document.querySelector(sel); return e ? e.getAttribute('href') : null", ["sel": selector])
    }
}

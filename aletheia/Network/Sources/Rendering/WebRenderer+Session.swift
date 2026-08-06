//
//  WebRenderer+Session.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import WebKit

extension WebRenderer {
    // one page's lifetime: construction, credential and script injection, and
    // proving the document is the real one before anything runs against it
    @MainActor
    struct Session {
        let page: WebPage
        let origin: String
        
        var bridge: Bridge { Bridge(page: page) }
        
        init(
            url: URL,
            credential: SourceCredential,
            capturing pattern: String,
            preload: String? = nil,
            storage: [String: String] = [:]
        ) async {
            let dataStore = WKWebsiteDataStore.default()
            await Self.inject(credential, for: url, into: dataStore.httpCookieStore)
            
            var configuration = WebPage.Configuration()
            configuration.websiteDataStore = dataStore
            
            // documentStart is the only point at which a native can still be
            // wrapped before the page's own code captures a reference to it
            for source in [storage.isEmpty ? nil : Capture.storage(storage), preload, Capture.script(matching: pattern)] {
                guard let source else { continue }
                configuration.userContentController.addUserScript(WKUserScript(
                    source: source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false,
                    in: .page
                ))
            }
            
            let page = WebPage(configuration: configuration)
            page.customUserAgent = credential.userAgent
            page.load(URLRequest(url: url))
            
            self.page = page
            self.origin = "\(url.scheme ?? "https")://\(url.host() ?? "")"
        }
        
        // polled from out here rather than inside a script: each check is its own
        // short call, so a reload or hydration swap costs a retry instead of an
        // unreachable promise
        func ready(anchor selector: String?, within timeout: Duration) async throws -> Bool {
            var waited: Duration = .zero
            var delay: Duration = .milliseconds(100)
            while waited < timeout {
                if try await settled(), try await present(selector) { return true }
                try await Task.sleep(for: delay)
                waited += delay
                delay = min(delay * 2, .seconds(1))
            }
            return false
        }
        
        // a fresh web view starts on an empty document that already reports
        // 'complete', so readyState alone says yes before the real page exists -
        // running a script there dies the moment the navigation commits
        private func settled() async throws -> Bool {
            try await bridge.bool(
                "return document.readyState === 'complete' && location.href.indexOf(origin) === 0",
                ["origin": origin]
            )
        }
        
        private func present(_ selector: String?) async throws -> Bool {
            guard let selector else { return true }
            return try await bridge.bool("return !!document.querySelector(sel)", ["sel": selector])
        }
        
        // navigating away invalidates any pending call, which resumes it as a
        // throw - the only way to unstick a wedged web content process
        func discard() {
            page.load(URLRequest(url: WebRenderer.blank))
        }
        
        private static func inject(_ credential: SourceCredential, for url: URL, into store: WKHTTPCookieStore) async {
            guard let host = url.host() else { return }
            for (name, value) in credential.cookies {
                guard let cookie = HTTPCookie(properties: [
                    .domain: host,
                    .path: "/",
                    .name: name,
                    .value: value,
                    .secure: "TRUE"
                ]) else { continue }
                await store.setCookie(cookie)
            }
        }
    }
}

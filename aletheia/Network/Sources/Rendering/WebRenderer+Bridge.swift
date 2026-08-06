//
//  WebRenderer+Bridge.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import WebKit

extension WebRenderer {
    // every evaluation goes through here so the content world is decided in one
    // place. `.page` is required, not stylistic: in an isolated world the site's
    // own bundle sees pristine globals and never touches what we installed
    @MainActor
    struct Bridge {
        let page: WebPage

        @discardableResult
        func call(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
            try await page.callJavaScript(script, arguments: arguments, contentWorld: .page)
        }

        func bool(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Bool {
            (try await call(script, arguments)) as? Bool ?? false
        }

        func string(_ script: String, _ arguments: [String: Any] = [:]) async throws -> String? {
            (try await call(script, arguments)) as? String
        }

        func strings(_ script: String, _ arguments: [String: Any] = [:]) async throws -> [String] {
            ((try await call(script, arguments)) as? [Any])?.compactMap { $0 as? String } ?? []
        }

        // -1 for anything that is not a number, so callers can tell "not yet"
        // from a real zero
        func number(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Int {
            let result = try await call(script, arguments)
            if let int = result as? Int { return int }
            if let double = result as? Double { return Int(double) }
            return -1
        }
    }
}

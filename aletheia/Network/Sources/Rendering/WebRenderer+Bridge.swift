//
//  WebRenderer+Bridge.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import WebKit

extension WebRenderer {
    // `.page` content world is required, not stylistic: in an isolated world the
    // site's own bundle sees pristine globals and never touches what we installed
    @MainActor
    struct Bridge {
        let page: WebPage

        // callJavaScript has no timeout of its own - a call into a suspended content
        // process never returns and never throws, which only surfaces in the
        // background (the poll loops above check the clock between calls, so a call
        // that never returns stops the clock ever being read). placed here rather
        // than at a call site so no caller can forget it. deliberately longer than
        // every poll budget above it, since a shorter one starts failing
        // slow-but-alive scripts, which is worse than the bug it fixes
        static let deadline: Duration = .seconds(30)

        // a javascript result is `Any?` and can't ride inside a Sendable enum, but
        // never needs to cross an isolation boundary either (both tasks and the
        // caller are on the main actor) - so the stream carries only which outcome
        // won, and the value is left here
        @MainActor
        private final class Slot {
            var value: Any?
        }

        @discardableResult
        func call(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
            enum Outcome: Sendable {
                case answered
                case overran
            }

            let (stream, continuation) = AsyncStream<Outcome>.makeStream()
            let slot = Slot()

            let work = Task { @MainActor in
                slot.value = try? await page.callJavaScript(
                    script, arguments: arguments, contentWorld: .page)
                continuation.yield(.answered)
            }
            let watchdog = Task { @MainActor in
                try? await Task.sleep(for: Self.deadline)
                continuation.yield(.overran)
            }
            defer {
                work.cancel()
                watchdog.cancel()
            }

            var outcomes = stream.makeAsyncIterator()
            switch await outcomes.next() {
            case .answered:
                return slot.value

            case .overran:
                // best effort - the stuck call may never notice, but navigating
                // away is the only lever there is, and a caller that throws can
                // at least be retried or failed
                page.load(URLRequest(url: WebRenderer.blank))
                throw RenderError.timedOut

            case nil:
                throw RenderError.noContent
            }
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

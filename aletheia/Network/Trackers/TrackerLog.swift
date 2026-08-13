//
//  TrackerLog.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation

// one format for every tracker request, so the log screen filtered to `trackers`
// reads as a transcript rather than as three services' private habits.
//
// this exists because TrackerError.unavailable is a catch-all: a decode failure
// and an unreachable host arrive at the reader as the same sentence, and neither
// says which. the error stays deliberately vague on screen - a reader cannot act
// on a coding key - and the detail goes here instead.
//
// levels do the filtering that a second category would otherwise do: the wire is
// .debug, an unhappy status is .warning, and a body we could not read is .error.
// so one category covers the whole feature and the noise is still separable
enum TrackerLog {
    static let category = "trackers"

    static func sent(_ tracker: Tracker, _ method: String, _ path: String) {
        AppLog.shared.log("[\(tracker.rawValue)] -> \(method) \(path)", level: .debug, category: category)
    }

    static func received(
        _ tracker: Tracker,
        _ method: String,
        _ path: String,
        status: Int,
        bytes: Int
    ) {
        let level: AppLog.Level = (200...299).contains(status) ? .debug : .warning
        AppLog.shared.log(
            "[\(tracker.rawValue)] <- \(status) \(method) \(path) (\(bytes) bytes)",
            level: level,
            category: category
        )
    }

    // the transport could not reach the service at all, so there is no status to
    // report and the url error is the whole story
    static func unreachable(_ tracker: Tracker, _ method: String, _ path: String, _ error: Error) {
        AppLog.shared.log(
            "[\(tracker.rawValue)] xx \(method) \(path) - \(error)",
            level: .error,
            category: category
        )
    }

    // the one that earns this file. a decode failure is the only tracker error
    // with no status code to explain it, and it is indistinguishable on screen
    // from the service being down - so the field that went wrong and a slice of
    // what actually arrived are recorded here
    static func undecodable(_ tracker: Tracker, _ path: String, expected: Any.Type, error: Error, body: Data) {
        AppLog.shared.log(
            "[\(tracker.rawValue)] could not read \(expected) from \(path) - \(reason(error)) | \(preview(body))",
            level: .error,
            category: category
        )
    }

    // MARK: Detail

    // DecodingError's own description is a paragraph with a context object in it.
    // what identifies the bug is the key path and the kind of mismatch, so that
    // is what is kept
    private static func reason(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return "\(error)" }

        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue)
            return keys.isEmpty ? "<root>" : keys.joined(separator: ".")
        }

        switch decoding {
        case let .keyNotFound(key, context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case let .typeMismatch(type, context):
            return "expected \(type) at \(path(context))"
        case let .valueNotFound(type, context):
            return "null where \(type) required at \(path(context))"
        case let .dataCorrupted(context):
            return "corrupt at \(path(context)) - \(context.debugDescription)"
        @unknown default:
            return "\(decoding)"
        }
    }

    // enough of the body to recognise, on one line. a log entry that wraps for
    // forty lines is one nobody scrolls past
    private static func preview(_ body: Data, limit: Int = 300) -> String {
        guard let text = String(data: body, encoding: .utf8) else {
            return "<\(body.count) bytes, not utf8>"
        }

        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)

        return flattened.count <= limit
            ? flattened
            : String(flattened.prefix(limit)) + "... (\(body.count) bytes)"
    }
}

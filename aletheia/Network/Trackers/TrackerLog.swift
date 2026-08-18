//
//  TrackerLog.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation

// TrackerError.unavailable is a catch-all on screen - a decode failure and an
// unreachable host read as the same sentence to the reader - so the detail
// goes here instead. levels do the filtering a second category would
// otherwise do: the wire is .debug, an unhappy status is .warning, and a body
// we could not read is .error
enum TrackerLog {
    static let category = "trackers"

    static func sent(_ tracker: Tracker, _ method: String, _ path: String) {
        AppLog.shared.log(
            "[\(tracker.rawValue)] -> \(method) \(path)", level: .debug, category: category)
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

    static func unreachable(_ tracker: Tracker, _ method: String, _ path: String, _ error: Error) {
        AppLog.shared.log(
            "[\(tracker.rawValue)] xx \(method) \(path) - \(error)",
            level: .error,
            category: category
        )
    }

    static func undecodable(
        _ tracker: Tracker, _ path: String, expected: Any.Type, error: Error, body: Data
    ) {
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
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context))"
        case .valueNotFound(let type, let context):
            return "null where \(type) required at \(path(context))"
        case .dataCorrupted(let context):
            return "corrupt at \(path(context)) - \(context.debugDescription)"
        @unknown default:
            return "\(decoding)"
        }
    }

    private static func preview(_ body: Data, limit: Int = 300) -> String {
        guard let text = String(data: body, encoding: .utf8) else {
            return "<\(body.count) bytes, not utf8>"
        }

        let flattened =
            text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)

        return flattened.count <= limit
            ? flattened
            : String(flattened.prefix(limit)) + "... (\(body.count) bytes)"
    }
}

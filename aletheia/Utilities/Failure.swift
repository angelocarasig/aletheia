//
//  Failure.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// the shape that carries an error across the view model/view boundary - no
// screen ever sees an Error directly
struct Failure: Equatable, Sendable {
    let title: String
    let message: String
    let isRetryable: Bool

    // falls back to title rather than an empty string - an empty sentence is
    // worse than a repeated one
    var sentence: String {
        message.isEmpty ? title : message
    }
}

extension Failure {
    // never String(describing:) as a fallback - that prints the case and its
    // associated values, which is debugger output, not a sentence
    init(_ error: Error, fallback: String = "Something Went Wrong") {
        if let describable = error as? DescribableError {
            title = describable.errorDescription ?? fallback
            message = describable.failureReason ?? describable.recoverySuggestion ?? ""
            isRetryable = describable.isRetryable
        } else if let localized = error as? LocalizedError {
            title = localized.errorDescription ?? fallback
            message = localized.failureReason ?? localized.recoverySuggestion ?? ""
            isRetryable = true
        } else {
            // e.g. a database error's text is sql, not a sentence - detail goes
            // to the log, the screen gets words a person can act on
            title = fallback
            message = "Something unexpected went wrong. Please try again."
            isRetryable = true
            AppLog.shared.log(
                "unpresentable error reached a screen - \(error)", level: .error,
                category: "failure")
        }
    }
}

// errorDescription is the title, failureReason is the sentence under it
protocol DescribableError: LocalizedError {
    var isRetryable: Bool { get }
}

extension DescribableError {
    // defaults true - a dead-end button costs more than one that turns out
    // not to help. types with permanent failures say so explicitly
    var isRetryable: Bool { true }
}

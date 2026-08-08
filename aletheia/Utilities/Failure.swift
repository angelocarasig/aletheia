//
//  Failure.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// what a view model hands a view when something went wrong. the error types
// already know how to describe themselves - this is only the shape that carries
// it across the boundary, so no screen ever sees an Error again
struct Failure: Equatable, Sendable {
    let title: String
    let message: String

    // whether offering a retry is honest. a chapter with no pages will never
    // have any, and a button that cannot work is worse than no button
    let isRetryable: Bool
}

extension Failure {
    // the whole point: an error that describes itself is used verbatim, and one
    // that does not falls back to something a person can still read. never
    // String(describing:) - that prints the case and its associated values,
    // which is debugger output rather than a sentence
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
            title = fallback
            message = error.localizedDescription
            isRetryable = true
        }
    }
}

// the contract an error type opts into to be shown. errorDescription is the
// title and failureReason is the sentence under it, which is what Foundation
// already means by them
protocol DescribableError: LocalizedError {
    var isRetryable: Bool { get }
}

extension DescribableError {
    // retrying a read is harmless, so an unstated answer offers the button - a
    // dead end costs more than a button that turns out not to help. types with
    // permanent cases say so explicitly
    var isRetryable: Bool { true }
}

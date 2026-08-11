//
//  TrackerError.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

enum TrackerError: DescribableError, Equatable {
    // the client id constant is empty - the app was built without one
    case notConfigured
    case signedOut
    // the token is gone or dead and refreshing cannot fix it. anilist reports
    // this as a 400 and myanimelist as a 401, so status codes alone misread one
    // of them as our bug
    case reauthenticationRequired
    case throttled(retryAfter: TimeInterval?)
    case cancelled
    case rejected(String)
    case unavailable

    // an auth failure stops the drain rather than failing every remaining item,
    // the same rule the download queue uses when the disk is full
    var isTerminal: Bool {
        switch self {
        case .notConfigured, .signedOut, .reauthenticationRequired: true
        default: false
        }
    }

    var isRetryable: Bool {
        !isTerminal && self != .cancelled
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Tracking isn't available in this build"
        case .signedOut: "Not signed in"
        case .reauthenticationRequired: "Sign in again to keep tracking"
        case .throttled: "Too many requests"
        case .cancelled: "Cancelled"
        case let .rejected(reason): reason
        case .unavailable: "The service isn't responding"
        }
    }

    var failureReason: String? {
        switch self {
        case .notConfigured: "This copy of the app was built without tracking credentials."
        case .signedOut: "Connect an account to sync your progress."
        // routine on anilist, whose token simply runs out after a year, and rare
        // on myanimelist. the reader does not care which, so neither says
        case .reauthenticationRequired: "Your connection has run out. Sign in again to carry on syncing."
        case .throttled: "The service asked us to slow down. This will retry on its own."
        case .cancelled: nil
        case .rejected: "The service refused the change."
        case .unavailable: "It may be down or unreachable. This will retry on its own."
        }
    }
}

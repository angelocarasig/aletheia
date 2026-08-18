//
//  ReaderPageError.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import Kingfisher

enum ReaderPageError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case unavailable(status: Int)
    case corrupt
    case failed
}

extension ReaderPageError {
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .failed: true
        case .corrupt: false
        case .unavailable(let status): !(400..<500).contains(status)
        }
    }
}

extension ReaderPageError: DescribableError {
    var errorDescription: String? {
        switch self {
        case .offline: "You're Offline"
        case .timedOut: "Took Too Long"
        case .unavailable: "Page Unavailable"
        case .corrupt: "Couldn't Read Page"
        case .failed: "Couldn't Load Page"
        }
    }

    var failureReason: String? {
        switch self {
        case .offline:
            "Connect to the internet to keep reading."
        case .timedOut:
            "The server took too long to respond."
        case .unavailable(let status):
            (400..<500).contains(status)
                ? "This page is no longer on the source's server."
                : "The source's server is having trouble. Try again in a moment."
        case .corrupt:
            "The file arrived damaged and can't be displayed."
        case .failed:
            "Something went wrong fetching this page."
        }
    }
}

// MARK: - Kingfisher

extension ReaderPageError {
    // the cell filters cancellation before calling this - a reused cell
    // cancelling its own load must never be mapped to a failure here
    init(_ error: KingfisherError) {
        switch error {
        case .responseError(let reason):
            switch reason {
            case .invalidHTTPStatusCode(let response):
                self = .unavailable(status: response.statusCode)
            case .URLSessionError(let underlying):
                self = Self.transport(underlying)
            default:
                self = .failed
            }

        case .processorError:
            self = .corrupt

        default:
            self = .failed
        }
    }

    private static func transport(_ error: Error) -> ReaderPageError {
        guard let url = error as? URLError else { return .failed }
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .failed
        }
    }
}

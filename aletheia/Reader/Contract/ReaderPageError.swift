//
//  ReaderPageError.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import Kingfisher

// page-scoped, deliberately separate from ReaderError. that type is about
// chapters - every case carries a chapter id and says things like "Empty
// Chapter" - and a single image failing to download is a different unit of
// failure. the cell has no chapter-level answer to give
enum ReaderPageError: Error, Equatable, Sendable {
    case offline
    case timedOut
    // the server answered, just not with an image. status is kept because 404
    // and 503 are the same sentence to a reader but not the same advice
    case unavailable(status: Int)
    case corrupt
    case failed
}

extension ReaderPageError {
    // a page that can never load, however many times it is retried. a missing
    // page is missing; a server having a bad minute is worth another tap
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .failed: true
        case .corrupt: false
        case let .unavailable(status): !(400..<500).contains(status)
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
        case let .unavailable(status):
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
    // the completion handler only ever hands back a KingfisherError, so this is
    // the single boundary where its vocabulary stops. cancellation never reaches
    // here - the cell drops it before mapping, because a reused cell cancelling
    // its own load is not a failure the reader should ever see
    init(_ error: KingfisherError) {
        switch error {
        case let .responseError(reason):
            switch reason {
            case let .invalidHTTPStatusCode(response):
                self = .unavailable(status: response.statusCode)
            case let .URLSessionError(underlying):
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

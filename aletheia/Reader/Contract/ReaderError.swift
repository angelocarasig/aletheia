//
//  ReaderError.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// every case is typed. the host never has to read a message to decide what
// happened - v2 string-matched "source is no longer available" out of an
// underlying error to detect a disconnected origin
enum ReaderError: Error, Equatable, Sendable {
    case notFound(ReaderChapter.ID)
    case noPages(ReaderChapter.ID)
    case unavailable(ReaderChapter.ID)
    case fetchFailed(ReaderChapter.ID, reason: String)
    case offline(ReaderChapter.ID)
}

extension ReaderError {
    var chapter: ReaderChapter.ID {
        switch self {
        case let .notFound(id), let .noPages(id), let .unavailable(id),
             let .fetchFailed(id, _), let .offline(id):
            id
        }
    }

    // a chapter that can never load here, however many times it is retried
    var isRetryable: Bool {
        switch self {
        case .fetchFailed, .offline: true
        case .notFound, .noPages, .unavailable: false
        }
    }
}

extension ReaderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound: "Chapter Not Found"
        case .noPages: "Empty Chapter"
        case .unavailable: "Source Unavailable"
        case .fetchFailed: "Failed to Load"
        case .offline: "You're Offline"
        }
    }

    var failureReason: String? {
        switch self {
        case .notFound:
            "This chapter is no longer in your library."
        case .noPages:
            "The source returned no pages for this chapter."
        case .unavailable:
            "The source this chapter came from has been removed or disabled. Downloaded chapters still open."
        case let .fetchFailed(_, reason):
            reason
        case .offline:
            "Connect to the internet to keep reading, or open a downloaded chapter."
        }
    }
}

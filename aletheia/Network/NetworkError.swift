//
//  NetworkError.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

enum NetworkError: DescribableError {
    case cancelled
    case offline
    case timeout
    case badResponse(status: Int, response: HTTPURLResponse)
    case encoding(Error)
    case decoding(type: String, error: DecodingError)
    case failed(URLError)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Request was cancelled"
        case .offline:
            return "No internet connection available"
        case .timeout:
            return "Request timed out"
        case .badResponse:
            return "Server Returned an Error"
        // one is us failing to build a request and the other is us failing to
        // read a reply. they shared a sentence that named the response, which
        // is the wrong direction for half of the pair
        case .encoding:
            return "Couldn't Send the Request"
        case .decoding:
            return "Unexpected Response"
        case .failed:
            return "Couldn't Reach the Server"
        }
    }

    // the sentence under the title. errorDescription names what happened; this
    // says what to do about it, which is the half a dead-end screen is missing
    var failureReason: String? {
        switch self {
        case .cancelled:
            return "The request was stopped before it finished."
        case .offline:
            return "Check your connection and try again."
        case .timeout:
            return "The server took too long to respond. Try again in a moment."
        // the status code is in the log line that accompanies every one of these,
        // so dropping it from the sentence loses nothing a person could use
        case .badResponse:
            return "The server responded unexpectedly."
        case .encoding:
            return "This app couldn't build the request."
        case .decoding:
            return "This app couldn't read the server's response."
        case .failed(let urlError):
            return urlError.localizedDescription
        }
    }

    // a transport problem is worth another go; a payload this app cannot parse
    // will fail identically every time
    var isRetryable: Bool {
        switch self {
        case .cancelled, .offline, .timeout, .badResponse, .failed:
            return true
        case .encoding, .decoding:
            return false
        }
    }

    var isCancellation: Bool {
        switch self {
        case .cancelled:
            return true
        case .failed(let urlError):
            return urlError.code == .cancelled
        default:
            return false
        }
    }
}

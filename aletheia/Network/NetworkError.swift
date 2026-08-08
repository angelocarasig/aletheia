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
        case .badResponse(let status, _):
            return "Invalid response with status code: \(status)"
        case .encoding:
            return "Failed to encode request body"
        case .decoding(let type, _):
            return "Failed to decode \(type)"
        case .failed(let urlError):
            return "Request failed: \(urlError.localizedDescription)"
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
        case .badResponse(let status, _):
            return "The server responded unexpectedly (status \(status))."
        case .encoding, .decoding:
            return "The response wasn't in a format this app understands."
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

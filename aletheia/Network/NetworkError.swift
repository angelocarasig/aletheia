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
        case .encoding:
            return "Couldn't Send the Request"
        case .decoding:
            return "Unexpected Response"
        case .failed:
            return "Couldn't Reach the Server"
        }
    }

    var failureReason: String? {
        switch self {
        case .cancelled:
            return "The request was stopped before it finished."
        case .offline:
            return "Check your connection and try again."
        case .timeout:
            return "The server took too long to respond. Try again in a moment."
        case .badResponse:
            return "The server responded unexpectedly."
        case .encoding:
            return "\(Constants.App.name) couldn't build the request."
        case .decoding:
            return "\(Constants.App.name) couldn't read the server's response."
        case .failed(let urlError):
            return urlError.localizedDescription
        }
    }

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

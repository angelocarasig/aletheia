//
//  NetworkError.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

enum NetworkError: LocalizedError {
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

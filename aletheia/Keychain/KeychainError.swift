//
//  KeychainError.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case encodingFailed(Error)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed (status \(status))"
        case .encodingFailed:
            return "Failed to encode the value for storage"
        case .decodingFailed:
            return "Failed to decode the stored value"
        }
    }
}

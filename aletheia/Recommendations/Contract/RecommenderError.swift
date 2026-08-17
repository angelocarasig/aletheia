//
//  RecommenderError.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

enum RecommenderError: DescribableError {
    case unavailable
    case unsupportedFormat(found: Int, supported: Int)
    case malformed(file: String, reason: String)
    case truncated(file: String, expected: Int, found: Int)
    case misaligned(file: String, array: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Recommendations Unavailable"
        case .unsupportedFormat:
            return "Recommendations Need an Update"
        case .malformed, .truncated, .misaligned:
            return "Couldn't Read the Recommendation Data"
        }
    }

    var failureReason: String? {
        switch self {
        case .unavailable:
            // the ordinary state on a fresh checkout, not a fault. the model is
            // gitignored, so this is what every machine but the one that built
            // it sees until the bundle is copied in
            return "This build doesn't include the recommendation model."
        case .unsupportedFormat(let found, let supported):
            return "The data is version \(found) and \(Constants.App.name) reads version \(supported)."
        case .malformed, .truncated, .misaligned:
            return "The recommendation data appears to be incomplete."
        }
    }

    // none of these clear by trying again. a missing bundle stays missing for the
    // life of the install, and a version mismatch needs a different build - a
    // retry button here would be an affordance that cannot work
    var isRetryable: Bool { false }

    // the reader gets the sentences above; this is what goes to the log, where a
    // file name and two byte counts are the whole diagnosis
    var detail: String {
        switch self {
        case .unavailable:
            return "no manifest.json in the bundle"
        case .unsupportedFormat(let found, let supported):
            return "formatVersion \(found), supported \(supported)"
        case .malformed(let file, let reason):
            return "\(file): \(reason)"
        case .truncated(let file, let expected, let found):
            return "\(file): expected \(expected) bytes, found \(found)"
        case .misaligned(let file, let array):
            return "\(file): array \(array) is not aligned for its element type"
        }
    }
}

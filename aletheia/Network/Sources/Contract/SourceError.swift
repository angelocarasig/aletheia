//
//  SourceError.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/2026.
//

import Foundation

enum SourceError: DescribableError {
    // an empty page list is a real answer on some sites: atsu.moe indexes web
    // novels alongside comics, and a novel chapter is a normal row with
    // pageCount 0 whose read call answers `{"pages": []}` with a 200
    case noPages

    var errorDescription: String? {
        switch self {
        case .noPages: "Nothing to Read"
        }
    }

    var failureReason: String? {
        switch self {
        case .noPages: "This chapter has no pages. Try another source for it."
        }
    }
}

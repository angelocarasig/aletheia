//
//  SourceError.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/2026.
//

import Foundation

// what a source says when the request worked and the answer is unusable. the
// network layer cannot express this - nothing failed there, the reply arrived
// intact and decoded - and RenderError cannot either, since its sentences name
// a page a headless renderer loaded and most sources have no renderer
enum SourceError: DescribableError {
    // a chapter whose content call returned no pages. an empty list is a real
    // answer on some sites: atsu.moe indexes web novels alongside comics, and a
    // novel chapter is a normal row with pageCount 0 whose read call answers
    // `{"pages": []}` with a 200. returning that as zero pages opens an empty
    // reader, which reads as the app breaking rather than the chapter being
    // unreadable
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

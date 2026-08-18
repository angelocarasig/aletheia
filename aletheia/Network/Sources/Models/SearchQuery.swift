//
//  SearchQuery.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

struct SearchQuery: Sendable {
    var text: String?
    var filters: [FilterSelection]
    var sort: SortSelection?
    var page: Int

    // set only by SourcePreset.query(), understood only by the source that declared it.
    // a preset carries no text, which is what makes routing on it safe - e.g. scans.gg
    // ranks popularity on an endpoint that ignores text and every filter, so it can't be
    // a sort option without silently discarding what the reader typed
    var route: String?
}

enum FilterSelection: Sendable, Hashable {
    case text(id: String, value: String)
    case number(id: String, value: Int)
    case select(id: String, optionID: String)
    case multiSelect(id: String, included: [String], excluded: [String])

    var id: String {
        switch self {
        case .text(let id, _), .number(let id, _), .select(let id, _), .multiSelect(let id, _, _):
            return id
        }
    }
}

// no direction field - an option IS a direction ("Title (A-Z)" and "Title (Z-A)"
// are two options, not one option plus a flag)
struct SortSelection: Sendable, Hashable {
    let optionID: String
}

//
//  SearchQuery.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

/// a search request: free text + the user's selected filters + sort + pagination.
struct SearchQuery: Sendable {
    var text: String?
    var filters: [FilterSelection]
    var sort: SortSelection?
    var page: Int

    // set only by SourcePreset.query() and understood only by the source that
    // declared it. a shelf is a ranking its api will not apply to a narrowed
    // result set - scans.gg ranks popularity on an endpoint that ignores text
    // and every filter - so it cannot be a sort option without silently
    // discarding what the reader typed. a preset carries no text, which is what
    // makes routing on it safe. nothing in the search ui can produce one
    var route: String?
}

/// a filter value the user chose (backend ids, not display labels).
enum FilterSelection: Sendable, Hashable {
    case text(id: String, value: String)
    case number(id: String, value: Int)
    case select(id: String, optionID: String)
    case multiSelect(id: String, included: [String], excluded: [String])

    var id: String {
        switch self {
        case let .text(id, _), let .number(id, _), let .select(id, _), let .multiSelect(id, _, _):
            return id
        }
    }
}

// no direction: an option IS a direction. "Title (A-Z)" and "Title (Z-A)" are
// two options, not one option and a flag - a source whose api takes them
// separately encodes that itself, the way every other per-source quirk is
struct SortSelection: Sendable, Hashable {
    let optionID: String
}

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

struct SortSelection: Sendable, Hashable {
    let optionID: String
    let ascending: Bool
}

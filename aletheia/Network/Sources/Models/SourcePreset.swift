//
//  SourcePreset.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

struct SourcePreset: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String?
    let order: Int
    var hidden: Bool
    let filters: [FilterSelection]
    let sort: SortSelection?

    init(
        id: String,
        name: String,
        subtitle: String? = nil,
        order: Int,
        hidden: Bool = false,
        filters: [FilterSelection] = [],
        sort: SortSelection? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.order = order
        self.hidden = hidden
        self.filters = filters
        self.sort = sort
    }

    func query(page: Int = 1) -> SearchQuery {
        SearchQuery(text: nil, filters: filters, sort: sort, page: page)
    }

    static func == (lhs: SourcePreset, rhs: SourcePreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

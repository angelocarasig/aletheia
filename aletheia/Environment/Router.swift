//
//  Router.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Observation
import SwiftUI

// cross-tab navigation. a tab root owns its own stack, so a view inside one has
// no way to reach another - and the alternative to this is a closure per
// destination, threaded down by hand and accumulating on Main one jump at a time
@Observable
final class Router {
    var tab: AppTab = .home

    // the token is what makes a repeat request land. the receiving screen seeds
    // itself once per token, so asking twice for the same text is two events
    // rather than one no-op - the seed guard on SearchScreen reads vm.query,
    // which is no longer empty the second time
    private(set) var search: Search?

    struct Search: Equatable {
        let text: String
        let token: Int
    }

    func searchAllSources(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let next = Search(text: trimmed, token: (search?.token ?? 0) + 1)
        search = next
        tab = .search
        AppLog.shared.log(
            "search all sources '\(trimmed)' token \(next.token)",
            category: "router")
    }
}

extension EnvironmentValues {
    @Entry var router = Router()
}

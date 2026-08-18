//
//  Router.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Observation
import SwiftUI

// a tab root owns its own NavigationStack - a view inside one has no way to
// reach another directly
@Observable
final class Router {
    var tab: AppTab = .home

    // the token is what makes a repeat request land - SearchScreen's seed
    // guard reads vm.query, which is no longer empty the second time, so
    // without a token asking twice for the same text is a no-op
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

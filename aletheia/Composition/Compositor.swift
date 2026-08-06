//
//  Compositor.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

struct Compositor: Sendable {
    let registry: Registry
    let db: Persistence
    let requester: AuthRequester
    let presenter: AuthPresenter

    init(database: DatabaseClient = .client) {
        let network = NetworkService()
        let presenter = AuthPresenter()
        let requester = AuthRequester(
            network: network,
            capturer: WebAuthCapturer(presenter: presenter, log: .shared),
            log: .shared
        )
        let renderer = WebRenderer(log: .shared)
        let sources: [Source] = [
            MangaFireSource(requester: requester, renderer: renderer),
            ComixSource(requester: requester, renderer: renderer)
        ]

        self.presenter = presenter
        self.requester = requester
        self.registry = Registry(sources: sources, database: database)
        self.db = Persistence(database: database)
    }
}

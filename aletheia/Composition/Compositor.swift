//
//  Compositor.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

struct Compositor: Sendable {
    let database: DatabaseClient
    let registry: Registry
    let db: Persistence
    let assets: Assets
    let requester: AuthRequester
    let presenter: AuthPresenter

    // no default - resolving the singleton opens the pool and runs migrations,
    // and that has to happen off the main actor during bootstrap
    init(database: DatabaseClient) {
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
            ComixSource(requester: requester, renderer: renderer),
            MangaDexSource(network: network),
            WeebCentralSource(network: network)
        ]

        self.database = database
        self.presenter = presenter
        self.requester = requester
        self.registry = Registry(sources: sources, database: database)
        self.assets = Assets(database: database, network: network)
        self.db = Persistence(database: database)
    }
}

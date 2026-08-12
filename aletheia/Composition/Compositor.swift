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
    let refresh: Refresh
    let downloads: Downloads
    let trackers: Trackers
    let requester: AuthRequester
    let presenter: AuthPresenter
    // the one funnel every request passes. exposed because a caller that builds
    // its own gets its own HostGate too, which is the cap silently not applying
    let network: NetworkConfiguration

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
            MangaDexSource(network: network),
            AtsumaruSource(network: network),
            WeebCentralSource(network: network),
            ScansGGSource(network: network),
            NHentaiSource(requester: requester, network: network),
            ToonilySource(requester: requester),
            MangaBallSource(requester: requester)
        ]

        self.database = database
        self.presenter = presenter
        self.requester = requester
        self.network = network
        let registry = Registry(sources: sources, database: database)

        self.registry = registry
        self.refresh = Refresh(database: database, registry: registry)
        let assets = Assets(database: database, registry: registry, network: network)
        self.assets = assets
        self.downloads = Downloads(database: database, registry: registry, store: assets.store)

        let trackerServices: [Tracker: any TrackerService] = [
            .anilist: AniListService(network: network),
            .myAnimeList: MyAnimeListService(network: network)
        ]
        let authority = TrackerAuthority(network: network, services: trackerServices)
        self.trackers = Trackers(database: database, authority: authority, services: trackerServices)

        self.db = Persistence(database: database)
    }
}

//
//  DetailsComposer.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import Observation

@MainActor
protocol DetailsApplying {
    func apply(_ stored: DetailsComposer.Stored)
}

@MainActor
protocol DetailsWriting {
    var saving: Bool { get }
    var failure: Failure? { get }

    func clear()
}

@MainActor
@Observable
final class DetailsComposer {
    let series: Series
    let library: Library
    let chapters: Chapters
    let sources: Sources
    let tracking: Tracking
    let identity: Identity
    let refresh: Refresh
    let recommendations: Recommendations
    let cadence: Cadence

    let entry: SeriesEntry

    let registry: Compositor.Registry
    let assets: Compositor.Assets
    let refresher: Compositor.Refresh
    let database: DatabaseClient

    var seriesId: SeriesRecord.ID?

    // scoped to resolving which series this is - once a row is observed, a
    // failure belongs to the child that produced it instead
    var failure: Failure?

    // cancelled and replaced when the screen resolves to a different row;
    // captures weak so closing the screen ends it
    var stream: Task<Void, Never>?

    // the row from opening this series from this source before, if any. reused
    // rather than duplicated on reopen; nil means nothing to reuse yet
    var held: SeriesRecord.ID?

    // distinct from seriesId != nil: seriesId is set when observation starts,
    // before any data arrives, so gating the skeleton on it would drop it early
    var applied = false

    var started = false

    init(
        entry: SeriesEntry,
        registry: Compositor.Registry,
        assets: Compositor.Assets,
        refresher: Compositor.Refresh,
        trackers: Compositor.Trackers,
        recommender: Recommender,
        impressions: Compositor.Impressions,
        database: DatabaseClient
    ) {
        self.entry = entry
        self.registry = registry
        self.assets = assets
        self.refresher = refresher
        self.database = database

        series = Series(
            registry: registry,
            assets: assets,
            database: database,
            stub: Self.stub(in: entry),
            referer: Self.opener(in: entry, registry: registry)?.descriptor.referer
        )
        library = Library(database: database)
        chapters = Chapters(database: database)
        sources = Sources(registry: registry, database: database)
        tracking = Tracking(host: trackers, database: database)
        identity = Identity(registry: registry, assets: assets, database: database)
        refresh = Refresh(
            entry: entry,
            refresher: refresher,
            registry: registry,
            trackers: trackers
        )
        recommendations = Recommendations(recommender: recommender, impressions: impressions)
        cadence = Cadence()
    }

    var ready: Bool { applied && !identity.isAmbiguous }

    var opener: Source? { Self.opener(in: entry, registry: registry) }

    nonisolated static func opener(
        in entry: SeriesEntry,
        registry: Compositor.Registry
    ) -> Source? {
        guard case .source(let slug, _) = entry else { return nil }
        return registry.source(slug: slug)
    }

    var stub: SeriesStub? { Self.stub(in: entry) }

    nonisolated static func stub(in entry: SeriesEntry) -> SeriesStub? {
        guard case .source(_, let stub) = entry else { return nil }
        return stub
    }

    func load() async {
        guard !started else { return }
        started = true

        switch entry {
        case .library(let id):
            observe(id)

        case .source:
            await resolve()
        }
    }

    // nothing to undo here - matching runs before anything reaches the network,
    // so this only ever needs to stop the observation
    func cancel() {
        identity.dismiss()
        stream?.cancel()
        stream = nil
    }
}

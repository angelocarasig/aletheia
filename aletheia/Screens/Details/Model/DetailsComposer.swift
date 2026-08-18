//
//  DetailsComposer.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import Observation

// a child fed by the observation. one bundle arrives for the whole screen and
// each child takes the part it owns, assigning only what changed - otherwise
// it redraws for a change that belonged to another child
@MainActor
protocol DetailsApplying {
    func apply(_ stored: DetailsComposer.Stored)
}

// a child that writes. both are kept here rather than on the screen so a write
// in one section leaves the others alone, and so a failure stays beside the
// thing that failed instead of arriving as a popup with no context.
//
// saving is derived, not stored - a child acting on a list keys its writes by
// row so one row saving does not dim the rest, and answers this from that
@MainActor
protocol DetailsWriting {
    var saving: Bool { get }
    var failure: Failure? { get }

    // a failure stays until it is resolved or the reader has read it, so the
    // one who shows it is the one who dismisses it
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

    // the kind that replaces the whole screen, raised only while working out
    // which series this is. once a row is being observed there is content to
    // keep, and anything that fails after that belongs to the child that
    // failed
    var failure: Failure?

    // the observation loop. cancelled and replaced whenever the screen resolves
    // to a different row, and weak inside so closing the screen ends it
    var stream: Task<Void, Never>?

    // opening a series writes it to the database whether or not it is in the
    // library, so it can be read offline. open the same one again later and
    // there is already a row waiting, holding whatever you read of it.
    //
    // this is that row. it is not used straight away, because the same series
    // may also be in the library under a different source. if it is, you are
    // asked, and answering "same series" folds this row into that one.
    // otherwise this row is reused as it stands.
    //
    // nil means this series has not been opened from this source before, so
    // there is nothing to reuse and a fresh row is written. without it every
    // reopen would write another copy and strand your progress on the last one
    var held: SeriesRecord.ID?

    // whether a first bundle has arrived. the screen holds its skeleton until
    // it has, and nothing else on here says the same thing - seriesId is set
    // when the observation starts, which is before any data comes back, so a
    // screen waiting on that would drop the skeleton with nothing to draw
    var applied = false

    // a one-way latch on load(), which works out which row this screen is for
    // and may write one. taken on the first call and never released, so the
    // work happens once however many times the screen asks
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

    // the screen draws from the database alone, so a row is all it waits on.
    // it waits on the disambiguation answer too, since drawing before that
    // would show a series the reader has not agreed this is
    var ready: Bool { applied && !identity.isAmbiguous }

    // the source this screen was opened from, nil when it was opened from the
    // library. a library entry has no source in hand and resolves one from its
    // highest priority origin once the first rows arrive
    var opener: Source? { Self.opener(in: entry, registry: registry) }

    nonisolated static func opener(
        in entry: SeriesEntry,
        registry: Compositor.Registry
    ) -> Source? {
        guard case .source(let slug, _) = entry else { return nil }
        return registry.source(slug: slug)
    }

    // the search result that was tapped, and everything known about the series
    // before the database or the network is touched. matching runs against it,
    // and the screen draws from it while the real row is still being resolved
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

    // backing out of the disambiguation prompt, the one question with no answer
    // that leaves a series on screen. nothing has been written at that point,
    // since matching runs before anything reaches the network, so there is
    // nothing to undo - only the observation to stop before the screen goes
    func cancel() {
        identity.dismiss()
        stream?.cancel()
        stream = nil
    }
}

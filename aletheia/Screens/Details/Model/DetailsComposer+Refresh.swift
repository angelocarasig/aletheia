//
//  DetailsComposer+Refresh.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import Tagged
import Observation
import struct SwiftUI.ImageResource

extension DetailsComposer {
    @MainActor
    @Observable
    final class Refresh: DetailsApplying {
        private(set) var state: State = .idle

        // every origin installed code can still reach. a refresh is the whole
        // set or it is a lie - an origin nothing ever asks goes permanently
        // stale while the reader is free to switch to it
        private(set) var origins: [Origin] = []

        private(set) var retrying: Set<Int64> = []
        private(set) var fetching = false

        var dismissal: Task<Void, Never>?

        // a one-way latch on prime(), which fetches chapters when a series
        // opened from a source has not been checked in a while. prime() is
        // called on every database change, and the fetch it starts is itself a
        // database change, so without the latch it would feed itself
        @ObservationIgnored private var primed = false

        // a one-way latch on adopt(). same reason - it is called on every
        // database change, and the latch holds it to a single join
        @ObservationIgnored private var adopted = false

        // whichever origin heads the list stands for the series, so its date is
        // what staleness is measured against
        @ObservationIgnored private var checkedDate: Date = .distantPast
        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        // prime() only fires on the journey where freshness is the point: the
        // reader is online, in a source's catalogue, and asked for this series
        // by name. a library-route open stays local, which is what
        // offline-first means
        private let entry: SeriesEntry
        private let refresher: Compositor.Refresh
        private let registry: Compositor.Registry

        init(
            entry: SeriesEntry,
            refresher: Compositor.Refresh,
            registry: Compositor.Registry
        ) {
            self.entry = entry
            self.refresher = refresher
            self.registry = registry
        }

        // from DetailsApplying
        func apply(_ stored: Stored) {
            seriesId = stored.series.id

            let mapped = stored.origins.compactMap { row -> Origin? in
                guard row.installed, !row.disconnected, !row.disabled else { return nil }
                guard let slug = row.sourceSlug, let source = registry.source(slug: slug) else { return nil }

                return Origin(
                    id: row.id,
                    slug: row.slug,
                    sourceSlug: slug,
                    name: row.sourceName ?? slug,
                    icon: source.descriptor.icon
                )
            }

            if origins != mapped { origins = mapped }

            checkedDate = mapped.first
                .flatMap { first in stored.origins.first { $0.id == first.id } }
                .map(\.chaptersFetchedDate)
                ?? stored.origins.first?.chaptersFetchedDate
                ?? .distantPast
        }

        var isRunning: Bool {
            if case .running = state { true } else { false }
        }

        var canStart: Bool { !origins.isEmpty && !isRunning }

        // every origin answers for itself: one dead source reports as one
        // failed row and the rest still land. results arrive as each finishes
        // rather than at the end, so the pill fills in.
        //
        // answers whether anything new arrived, because the language and
        // scanlator lists are per-origin and either can gain entries from a
        // single new chapter
        @discardableResult
        func walk(metadata: Bool) async -> Bool {
            guard canStart else { return false }

            let targets = origins
            dismissal?.cancel()
            fetching = true
            defer { fetching = false }

            // if a library walk is holding this series in its queue, it is
            // about to fetch exactly what this is fetching. tell it not to
            // bother - pulling to refresh means check this one now, and the
            // walk arriving later to repeat it is two requests for one answer
            if let seriesId { refresher.dequeue(series: seriesId.rawValue) }

            var outcomes = targets.map {
                Outcome(id: $0.id, name: $0.name, icon: $0.icon)
            }
            state = .running(outcomes)

            await withTaskGroup(of: (Int64, OriginRefresher.Outcome).self) { group in
                for target in targets {
                    guard let source = registry.source(slug: target.sourceSlug) else { continue }
                    let originId = OriginRecord.ID(rawValue: target.id)

                    group.addTask { [refresher] in
                        if metadata {
                            await refresher.metadata(
                                source: source,
                                seriesSlug: target.slug,
                                originId: originId
                            )
                        }

                        return (
                            target.id,
                            await refresher.chapters(
                                source: source,
                                seriesSlug: target.slug,
                                originId: originId
                            )
                        )
                    }
                }

                for await (originId, result) in group {
                    guard let index = outcomes.firstIndex(where: { $0.id == originId }) else { continue }
                    outcomes[index].result = result
                    state = .running(outcomes)
                }
            }

            state = .finished(outcomes)
            schedule()

            return outcomes.contains { if case .added = $0.result { true } else { false } }
        }

        // the same unit everything else calls, so a retry while a library run
        // is already checking this origin joins that fetch instead of racing
        // it. offered on every failure rather than only the retryable ones:
        // which is which is known at the throw and not stored, and four of the
        // reasons this row can print end with the words "try again"
        func retry(_ originId: Int64) async {
            guard !retrying.contains(originId) else { return }
            guard let target = origins.first(where: { $0.id == originId }) else { return }
            guard let source = registry.source(slug: target.sourceSlug) else { return }

            retrying.insert(originId)
            defer { retrying.remove(originId) }

            _ = await refresher.chapters(
                source: source,
                seriesSlug: target.slug,
                originId: OriginRecord.ID(rawValue: originId)
            )
        }

        // a series whose row exists but whose chapters never landed would
        // otherwise never try again - matching short-circuits before the row is
        // written, which is the only other caller. it answers two cases with
        // one condition: never fetched, since distantPast is older than any
        // threshold, and fetched long enough ago to be worth asking again.
        //
        // claims its latch and leaves, because this runs inside the observation
        // loop - awaiting a fetch there holds the loop open for its whole
        // length, and a cover finishing meanwhile would not reach the screen
        // until the chapters did
        func prime() {
            guard !primed, !fetching else { return }
            guard case .source = entry else { return }
            guard checkedDate < Date.now.addingTimeInterval(-Constants.Refresh.staleAfter) else { return }
            guard !origins.isEmpty else { return }

            let targets = origins
            primed = true
            fetching = true

            Task { [weak self, refresher, registry] in
                // every origin, not the head of the list. a stale origin and a
                // fresh one render identically, so asking one leaves the rest
                // permanently behind with nothing on screen able to say so
                await withTaskGroup(of: Void.self) { group in
                    for target in targets {
                        guard let source = registry.source(slug: target.sourceSlug) else { continue }

                        group.addTask {
                            _ = await refresher.chapters(
                                source: source,
                                seriesSlug: target.slug,
                                originId: OriginRecord.ID(rawValue: target.id)
                            )
                        }
                    }
                }

                self?.fetching = false
            }
        }

        // a fetch this screen started before it was closed is still running in
        // the shared unit, and its answer is owed to whoever asks. joining
        // takes that answer rather than issuing a second request - without it
        // the rebuilt pill can only show that something is happening, then
        // vanish when it stops
        func adopt() {
            guard !adopted, !isRunning else { return }

            let live = origins.filter { refresher.isChecking(origin: $0.id) }
            guard !live.isEmpty else { return }

            adopted = true
            Task { [weak self] in await self?.join(live) }
        }

        func join(_ live: [Origin]) async {
            var outcomes = live.map {
                Outcome(id: $0.id, name: $0.name, icon: $0.icon)
            }
            state = .running(outcomes)

            await withTaskGroup(of: (Int64, OriginRefresher.Outcome?).self) { group in
                for target in live {
                    let originId = OriginRecord.ID(rawValue: target.id)

                    group.addTask { [refresher] in
                        (target.id, await refresher.join(originId: originId))
                    }
                }

                for await (originId, outcome) in group {
                    guard
                        let outcome,
                        let index = outcomes.firstIndex(where: { $0.id == originId })
                    else { continue }

                    outcomes[index].result = outcome
                    state = .running(outcomes)
                }
            }

            state = .finished(outcomes)
            schedule()
        }

        // the finished pill is a result, not a permanent row - it says what
        // happened and then gets out of the way
        func schedule() {
            dismissal?.cancel()
            dismissal = Task { [weak self] in
                try? await Task.sleep(for: Self.linger)
                guard !Task.isCancelled else { return }
                self?.state = .idle
            }
        }

        // one origin fetched outside the walk - attaching a source to a series
        // already on screen. the pair exists because the fetch belongs to
        // whoever attached it, while the pill it shows in belongs here
        func began(_ origin: Origin) {
            state = .running([Outcome(id: origin.id, name: origin.name, icon: origin.icon)])
        }

        func ended(_ origin: Origin, _ result: OriginRefresher.Outcome?) {
            state = .finished([
                Outcome(id: origin.id, name: origin.name, icon: origin.icon, result: result)
            ])
            schedule()
        }
    }
}

// the two entry points, on the composer because a run that brings in chapters
// changes what the ranking sheets can offer, and covers are add-only on a
// metadata refresh - both belong to other parts of the screen
extension DetailsComposer {
    func refresh() async {
        await run(metadata: true)
    }

    func refreshChapters() async {
        await run(metadata: false)
    }

    private func run(metadata: Bool) async {
        let added = await refresh.walk(metadata: metadata)

        if metadata, let seriesId { assets.enqueue(series: seriesId) }

        // both lists are per-origin and either can gain entries from a single
        // new chapter, so they are re-read once for the whole run rather than
        // per origin that happened to add something
        guard added else { return }

        await sources.languages()
        await sources.scanlators()
    }
}

extension DetailsComposer.Refresh {
    static let linger: Duration = .seconds(3)

    struct Origin: Sendable, Identifiable, Hashable {
        let id: Int64
        let slug: String
        let sourceSlug: String
        let name: String
        let icon: ImageResource?
    }

    // one entry per origin the run is talking to, so a three-source series
    // shows three answers rather than one summary that hides which is broken.
    // running and finished carry the same list - the difference is only whether
    // entries can still change
    enum State: Equatable {
        case idle
        case running([Outcome])
        case finished([Outcome])

        var outcomes: [Outcome] {
            switch self {
            case .idle: []
            case .running(let outcomes), .finished(let outcomes): outcomes
            }
        }
    }

    // nil is still checking - the unit answers with one of three things, and
    // "has not answered yet" is a property of the row rather than a fourth
    // answer the unit could ever return
    struct Outcome: Identifiable, Equatable {
        let id: Int64
        let name: String
        let icon: ImageResource?
        var result: OriginRefresher.Outcome?
    }
}

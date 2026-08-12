//
//  DetailsViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import SwiftUI
import GRDB
import Tagged
import Observation

@MainActor
@Observable
final class DetailsViewModel {
    private let entry: SeriesEntry
    private let database: DatabaseClient
    private let registry: Compositor.Registry
    private let assets: Compositor.Assets
    private let refresher: Compositor.Refresh
    private let trackers: Compositor.Trackers

    // a cover swapping from its remote url to its downloaded file changes the
    // kingfisher cache key, which replays the fade. first answer wins for the life
    // of this screen, so the local file is picked up on the next open instead
    @ObservationIgnored private var resolved: [String: URL] = [:]

    private(set) var snapshot: Snapshot?
    private(set) var candidates: [DetailsDisambiguation.Candidate] = []
    private(set) var failure: Failure?
    private(set) var isSaving = false
    private(set) var isFetchingChapters = false
    private(set) var refreshState: RefreshState = .idle
    // by origin, because a series can be failing on one source and healthy on
    // another, and each row retries for itself
    private(set) var retrying: Set<Int64> = []
    // a mutation the reader asked for that did not happen. separate from
    // `failure`, which replaces the whole screen - here the content is still
    // valid and only the action failed, so it is raised and dismissed
    private(set) var actionFailure: Failure?

    func clearActionFailure() { actionFailure = nil }


    // read by the screen to ask whether a library run is touching this series -
    // its own pill would otherwise sit idle while chapters land underneath it
    private(set) var seriesId: SeriesRecord.ID?
    private var held: SeriesRecord.ID?
    private var started = false
    private var primed = false
    private var adopted = false
    private var stream: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?

    private static let outcomeDuration: Duration = .seconds(3)
    // enough rows that the right series is on screen without a search field,
    // few enough that ranking still means something
    nonisolated private static let mergeCandidateLimit = 10

    // the source that opened this screen, nil for a library entry - which resolves
    // its source from the primary origin once the first snapshot lands instead
    private var opener: Source? {
        guard case .source(let slug, _) = entry else { return nil }
        return registry.source(slug: slug)
    }

    private var openerStub: SeriesStub? {
        guard case .source(_, let stub) = entry else { return nil }
        return stub
    }

    init(
        entry: SeriesEntry,
        registry: Compositor.Registry,
        assets: Compositor.Assets,
        refresher: Compositor.Refresh,
        trackers: Compositor.Trackers,
        database: DatabaseClient
    ) {
        self.entry = entry
        self.registry = registry
        self.assets = assets
        self.refresher = refresher
        self.trackers = trackers
        self.database = database
    }

    private func artwork(_ remote: URL?, path: String?) -> URL? {
        guard let remote else { return assets.local(for: path) }
        if let seen = resolved[remote.absoluteString] { return seen }

        let url = assets.local(for: path) ?? remote
        resolved[remote.absoluteString] = url
        return url
    }

    // MARK: - Presentation

    var title: String { snapshot?.title ?? openerStub?.title ?? "" }
    var cover: URL? { snapshot?.cover ?? openerStub?.cover }
    var synopsis: AttributedString? { snapshot?.synopsis }
    var authors: [String] { snapshot?.authors ?? [] }
    var tags: [String] { snapshot?.tags ?? [] }
    var classification: Classification? { snapshot?.classification }
    var publication: Publication? { snapshot?.publication }
    var inLibrary: Bool { snapshot?.inLibrary ?? false }
    var status: Status { snapshot?.status ?? .planning }
    var chapters: [DetailsChapters.Chapter] { snapshot?.chapters ?? [] }
    var origins: [DetailsSources.Origin] { snapshot?.origins ?? [] }

    private(set) var scanlatorGroups: [ScanlatorOrder.Origin] = []
    private(set) var isLoadingScanlators = false

    private(set) var languageOrder: [LanguageOrder.Language] = []
    private(set) var isLoadingLanguages = false

    private(set) var mergeCandidates: [DetailsMerge.Candidate] = []
    private(set) var isLoadingMergeCandidates = false

    var covers: [DetailsCovers.Cover] { snapshot?.covers ?? [] }
    var titles: [DetailsTitles.Title] { snapshot?.titles ?? [] }
    var synopses: [DetailsEdit.Synopsis] { snapshot?.synopses ?? [] }
    var metadataChoices: [DetailsEdit.Metadata] { snapshot?.choices ?? [] }
    var readCount: Int { snapshot?.readCount ?? 0 }
    var lastReadDate: Date? { snapshot.flatMap { $0.lastReadDate > .distantPast ? $0.lastReadDate : nil } }
    var lastMetadataFetch: Date? { snapshot.flatMap { $0.metadataFetchedDate > .distantPast ? $0.metadataFetchedDate : nil } }

    // an empty chapter list only means "none" once a fetch has actually landed
    var hasFetchedChapters: Bool { (snapshot?.chaptersFetchedDate ?? .distantPast) > .distantPast }

    // the origins a refresh would speak to, named. the screen asks the shared
    // unit which of them are in flight and rebuilds the rows from that - its own
    // refreshState died with the last view model, but the origins did not
    var refreshables: [Snapshot.Refreshable] { snapshot?.refreshables ?? [] }

    var canToggleLibrary: Bool { seriesId != nil && !isSaving }
    var needsDisambiguation: Bool { !candidates.isEmpty }
    var isRefreshing: Bool {
        if case .running = refreshState { true } else { false }
    }
    var canRefresh: Bool { !refreshTargets.isEmpty && !isRefreshing }

    // the screen renders from the database alone, so a row is all it waits on
    var isReady: Bool { snapshot != nil && !needsDisambiguation }

    // every cover request has to carry the referer of the site that served it or
    // the host 403s. taken from the stored origin, so it still resolves for a
    // series whose source is no longer installed
    var referer: URL? { snapshot?.referer ?? opener?.descriptor.referer }

    // the action row counts what this series is in; the picker needs every collection
    // so there is something to add it to
    var collections: [CollectionPicker.Item] { (snapshot?.collections ?? []).filter(\.contains) }

    // MARK: - Tracking

    var links: [DetailsTracking.Link] { snapshot?.links ?? [] }

    // connected accounts, in a fixed order so the two rows never swap places
    var trackerAccounts: [Tracker] {
        Tracker.allCases.filter { trackers.accounts[$0] != nil }
    }

    // connected but unable to push until the reader signs in again. read from the
    // credential rather than from the in-memory dead set, so it answers the same
    // on the launch after the token died as it did the moment it died
    var trackersNeedingSignIn: Set<Tracker> {
        trackers.needingSignIn
    }

    var syncingTrackers: Set<Tracker> {
        guard let seriesId else { return [] }
        return trackers.syncing(series: seriesId.rawValue)
    }

    // what a tracker row compares itself against: the same watermark the push
    // itself sends, so the row and the wire can never disagree about what local
    // progress is
    var localProgress: Int { snapshot?.localProgress ?? 0 }

    func searchTrackers(_ query: String, on tracker: Tracker, adult: Bool) async throws -> [TrackerCandidate] {
        try await trackers.search(tracker, query: query, adult: adult)
    }

    // which remote entries on this service are already spoken for by a DIFFERENT
    // series in the library. two library rows pointing at one remote entry means
    // both push their own progress to it and each keeps undoing the other, and
    // nothing on the entry itself says which one is winning - so the warning has
    // to name the other series rather than just flagging a clash
    func trackerConflicts(on tracker: Tracker) async -> [Int64: String] {
        let current = seriesId
        return (try? await database.reader.read { db -> [Int64: String] in
            let rows = try SeriesTrackerRecord
                .filter(SeriesTrackerRecord.Columns.tracker == tracker.rawValue)
                .fetchAll(db)
                .filter { $0.seriesId != current }

            guard !rows.isEmpty else { return [:] }

            let titles = try RichfulEntryView
                .filter(rows.map(\.seriesId.rawValue).contains(RichfulEntryView.Columns.seriesId))
                .fetchAll(db)
                .reduce(into: [Int64: String]()) { out, entry in
                    out[entry.seriesId] = entry.title
                }

            return rows.reduce(into: [Int64: String]()) { out, row in
                out[row.remoteId] = titles[row.seriesId.rawValue] ?? "another series"
            }
        }) ?? [:]
    }

    // pasting a link or an id is the escape hatch for the case search cannot
    // reach: a title romanised differently everywhere, or an entry buried past
    // fifty results. accepts a bare id or any url ending in one
    func resolveTracker(_ text: String, on tracker: Tracker) async -> TrackerCandidate? {
        guard let id = Self.remoteId(in: text) else { return nil }
        guard let entry = try? await trackers.entry(tracker, remoteId: id) else { return nil }
        return TrackerCandidate(
            id: entry.remoteId,
            title: entry.title,
            totalChapters: entry.totalChapters
        )
    }

    // what the reader's own list says about one entry, fetched when they open it
    // rather than for every search result - fifty of these would be fifty
    // requests against a budget of thirty a minute
    func trackerEntry(_ tracker: Tracker, remoteId: Int64) async throws -> TrackerEntry {
        try await trackers.entry(tracker, remoteId: remoteId)
    }

    // a URL only. a bare number is a title as often as it is an id - "20", "86",
    // "1984" are all real series - and treating one as an id turned a search for
    // them into a single wrong result with no way to tell why
    nonisolated static func remoteId(in text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("anilist.co") || trimmed.contains("myanimelist.net") else { return nil }

        // .../manga/101177/kanojo-mo-kanojo - the id is the first all-digit
        // component after the host, never the slug beside it
        return trimmed
            .split(whereSeparator: { "/?#".contains($0) })
            .compactMap { Int64($0) }
            .first
    }

    // the account's own scale, or a sane default while signed out - it is a
    // property of the account rather than of this series, so it is never stored
    // on the link row
    func scoreFormat(for tracker: Tracker) -> ScoreFormat {
        tracker.fixedScoreFormat ?? trackers.accounts[tracker]?.scoreFormat ?? .point10
    }

    // throws rather than raising its own alert: the control that started this
    // reports on it, and an alert over an inline failure is the same fact told
    // twice - the rule the chapter-fetch path already learned
    func link(_ candidate: TrackerCandidate, on tracker: Tracker, update: TrackerUpdate) async throws {
        guard let seriesId else { return }
        isSaving = true
        defer { isSaving = false }

        try await trackers.link(
            series: seriesId,
            tracker: tracker,
            candidate: candidate,
            status: update.status ?? status,
            update: update
        )
    }

    func unlink(_ link: DetailsTracking.Link, removeRemote: Bool = false) async {
        guard let row = try? await stored(link) else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await trackers.unlink(row, removeRemote: removeRemote)
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Unlink")
        }
    }

    // the one caller allowed to lower a number, and the only path that may write
    // to an entry the service already calls finished
    func editTracker(_ link: DetailsTracking.Link, update: TrackerUpdate) async throws {
        guard let row = try await stored(link) else { throw TrackerError.unavailable }
        isSaving = true
        defer { isSaving = false }

        try await trackers.edit(row, update: update)
    }

    // the remote is ahead and the reader said to accept it
    // the queue kept every pending column, so this is the walk being asked to
    // run now rather than at its next wake - not a second way to push
    func retryTracker(_ link: DetailsTracking.Link) async {
        guard let row = try? await stored(link) else { return }
        trackers.retry(row)
    }

    func catchUp(to link: DetailsTracking.Link) async {
        await catchUp(to: link.progress)
    }

    // reuses the batch mark rather than inventing a second way to write read
    // state, so it enqueues like any other read - the service this number came
    // from is already at it and declines the write, while a sibling service that
    // is behind is brought up, which is what the reader asked for
    func catchUp(to progress: Int) async {
        let numbers = chapters
            .map(\.number)
            .filter { $0 <= Double(progress) }

        await mark(read: true, numbers: numbers)
    }

    // this app is further along, so every linked service is told - they are all
    // behind the same read state, and syncing one while leaving the other stale
    // is how the two drift apart for good.
    //
    // enqueue only writes a link whose pending value beats what the service
    // holds, so a service already at or past the watermark is left untouched
    func pushLocalToTrackers() async {
        guard let seriesId else { return }

        do {
            try await database.writer.write { db in
                try SeriesTrackerRecord.enqueue(for: seriesId, in: db)
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Sync")
            return
        }

        trackers.flush()
    }

    private func stored(_ link: DetailsTracking.Link) async throws -> SeriesTrackerRecord? {
        try await database.reader.read { db in
            try SeriesTrackerRecord.fetchOne(db, key: link.id)
        }
    }
    var availableCollections: [CollectionPicker.Item] { snapshot?.collections ?? [] }

    // MARK: - Entry

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

    // tier one then tier two, both against the database and both before anything
    // reaches the network
    private func resolve() async {
        guard let source = opener, let stub = openerStub else {
            failure = Failure(
                title: "Source Unavailable",
                message: "No installed source can open this series.",
                isRetryable: false
            )
            return
        }

        let match = try? await database.reader.read { db in
            try SeriesRecord.match(stub, from: source.descriptor.slug, in: db)
        }

        held = match?.existing

        switch match?.outcome {
        case .inLibrary(let id):
            observe(id)

        case .candidates(let ids):
            await loadCandidates(ids)

        case .unmatched, nil:
            await settle()
        }
    }

    // where the flow lands once no library series claims this one: the row tier
    // one held if there was one, otherwise a series that does not exist yet
    private func settle() async {
        if let held {
            observe(held)
        } else {
            await create(into: nil)
        }
    }

    // MARK: - Disambiguation

    func attach(to target: Int64) async {
        let id = SeriesRecord.ID(rawValue: target)
        candidates = []

        // the held row already owns an origin for this source, so it moves rather
        // than being fetched a second time
        guard let held else {
            await create(into: id)
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                try Self.reparent(from: held, to: id, in: db)
            }
            self.held = nil
            observe(id)
        } catch {
            failure = Failure(error, fallback: "Couldn't Load Series")
        }
    }

    func keepSeparate() async {
        candidates = []
        await settle()
    }

    // backing out of the choice entirely. nothing has been written at this point -
    // matching runs before anything reaches the network - so there is nothing to
    // undo, only work to stop
    func cancel() {
        candidates = []
        stream?.cancel()
        stream = nil
    }

    private func loadCandidates(_ ids: [SeriesRecord.ID]) async {
        do {
            let rows = try await database.reader.read { db in
                try Self.candidates(for: ids, in: db)
            }

            candidates = rows.map { row in
                DetailsDisambiguation.Candidate(
                    id: row.id,
                    title: row.title,
                    authors: row.authors,
                    synopsis: row.synopsis,
                    cover: artwork(row.cover, path: row.path),
                    referer: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.referer,
                    read: row.read,
                    total: row.total,
                    lastReadDate: row.lastReadDate > .distantPast ? row.lastReadDate : nil,
                    addedDate: row.addedDate
                )
            }
        } catch {
            // a background load. the screen keeps what it has rather than nagging
            AppLog.shared.log("candidates failed - \(error)", category: "details")
            await settle()
        }
    }

    // MARK: - Create

    // the only path that fetches. everything else on this screen reads rows that
    // are already there
    private func create(into existing: SeriesRecord.ID?) async {
        guard let source = opener, let stub = openerStub else {
            // a library entry always carries its row id, so it never arrives here
            failure = Failure(
                title: "Source Unavailable",
                message: "No installed source can open this series.",
                isRetryable: false
            )
            return
        }

        do {
            let detail = try await source.details(seriesSlug: stub.slug)
            let sourceSlug = source.descriptor.slug
            let cover = stub.cover

            let ids = try await database.writer.write { db -> (SeriesRecord.ID, OriginRecord.ID) in
                guard let sourceId = try SourceRecord
                    .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                    .filter(SourceRecord.Columns.slug == sourceSlug)
                    .fetchOne(db)
                else { throw DetailsError.missingIdentifier }

                // the details response carries the canonical slug, and the stub may
                // have been opened under an older one - both have to be checked or
                // a series already stored is created a second time
                let known = try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter([detail.slug, stub.slug].contains(OriginRecord.Columns.slug))
                    .fetchOne(db)

                if let known, let originId = known.id {
                    return (known.seriesId, originId)
                }

                return try Self.create(
                    from: detail,
                    sourceId: sourceId,
                    matching: cover,
                    into: existing,
                    in: db
                )
            }

            observe(ids.0)
            assets.enqueue(series: ids.0)

            // attaching to an existing series happens behind a screen that is
            // already showing chapters from other origins, so the fetch gets the
            // refresh pill - badged with the new source's icon - rather than
            // passing silently. a fresh open keeps the skeleton as its indicator
            if existing != nil {
                var outcome = RefreshState.Outcome(
                    id: ids.1.rawValue,
                    name: source.descriptor.name,
                    icon: source.descriptor.icon,
                    result: nil
                )
                refreshState = .running([outcome])
                outcome.result = await refresher.chapters(
                    source: source,
                    seriesSlug: stub.slug,
                    originId: ids.1
                )
                refreshState = .finished([outcome])
                schedule()
            } else {
                _ = await refresher.chapters(source: source, seriesSlug: stub.slug, originId: ids.1)
            }
        } catch {
            failure = Failure(error, fallback: "Couldn't Load Series")
        }
    }

    // MARK: - Observation

    // one observation feeds the whole screen. every write below lands here rather
    // than being read back by hand, so nothing reloads itself after a change
    private func observe(_ id: SeriesRecord.ID) {
        seriesId = id
        failure = nil
        stream?.cancel()

        // weak, so the screen going away releases the view model rather than the
        // observation holding it open. the loop then ends on its next emission
        stream = Task { [weak self, database, registry] in
            let observation = ValueObservation.tracking { db -> Stored? in
                guard
                    let series = try SeriesRecord.fetchOne(db, key: id.rawValue),
                    let entry = try RichfulEntryView
                        .filter(RichfulEntryView.Columns.seriesId == id.rawValue)
                        .fetchOne(db)
                else { return nil }

                let rows = try Self.chapters(for: id, in: db)

                return Stored(
                    series: series,
                    entry: entry,
                    chapters: rows,
                    // mapped here rather than in Snapshot.init: this closure runs
                    // on the database queue, and a series with four hundred
                    // chapters was rebuilding every row on the main actor on
                    // every emission - measured at ~700ms after a bulk insert
                    display: Self.display(rows, registry: registry),
                    origins: try Self.origins(for: id, in: db),
                    covers: try Self.covers(for: id, in: db),
                    titles: try Self.titles(for: id, in: db),
                    collections: try Self.collections(for: id, in: db),
                    trackers: try SeriesTrackerRecord
                        .filter(SeriesTrackerRecord.Columns.seriesId == id.rawValue)
                        .fetchAll(db),
                    watermark: try SeriesTrackerRecord.watermark(for: id, in: db)
                )
            }

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    guard let stored else { continue }
                    let formats = self.trackers.accounts.mapValues(\.scoreFormat)
                    self.snapshot = Snapshot(stored, registry: registry, formats: formats) { remote, path in
                        self.artwork(remote, path: path)
                    }
                    self.adopt()
                    self.prime()
                }
            } catch {
                // a background load. the screen keeps what it has rather than nagging
                AppLog.shared.log("observation failed - \(error)", category: "details")
            }
        }
    }

    // MARK: - Refresh

    // which source speaks for this series, and under what slug. a sourced entry
    // knows already; a library one takes every origin it can still speak to.
    // an origin nothing ever asks goes permanently stale while the reader is
    // free to switch to it, so a refresh is the whole set or it is a lie
    private var refreshTargets: [Snapshot.Refreshable] {
        snapshot?.refreshables ?? []
    }

    func refresh() async {
        await run(metadata: true)
    }

    func refreshChapters() async {
        await run(metadata: false)
    }

    // every origin answers for itself: one dead source reports as one failed row
    // and the rest still land. results arrive as each origin finishes rather than
    // at the end, so the pill fills in
    private func run(metadata: Bool) async {
        guard !isRefreshing else { return }
        let targets = refreshTargets
        guard !targets.isEmpty else { return }

        dismissal?.cancel()
        isFetchingChapters = true
        defer { isFetchingChapters = false }

        // if a library walk is holding this series in its queue, it is about to
        // fetch exactly what this is fetching. tell it not to bother - pulling
        // to refresh means check this one now, and the walk arriving later to
        // repeat the work is two requests for one answer
        if let seriesId { refresher.dequeue(series: seriesId.rawValue) }

        var outcomes = targets.map {
            RefreshState.Outcome(id: $0.originId, name: $0.name, icon: $0.icon, result: nil)
        }
        refreshState = .running(outcomes)

        await withTaskGroup(of: (Int64, OriginRefresher.Outcome).self) { group in
            for target in targets {
                guard let source = registry.source(slug: target.sourceSlug) else { continue }
                let originId = OriginRecord.ID(rawValue: target.originId)
                group.addTask { [refresher] in
                    if metadata {
                        await refresher.metadata(
                            source: source,
                            seriesSlug: target.slug,
                            originId: originId
                        )
                    }
                    let result = await refresher.chapters(
                        source: source,
                        seriesSlug: target.slug,
                        originId: originId
                    )
                    return (target.originId, result)
                }
            }

            for await (originId, result) in group {
                guard let index = outcomes.firstIndex(where: { $0.id == originId }) else { continue }
                outcomes[index].result = result
                refreshState = .running(outcomes)
            }
        }

        // covers are add-only on refresh, so a refresh can introduce new ones
        if metadata, let seriesId { assets.enqueue(series: seriesId) }

        // both lists are per-origin and both can gain entries from a single new
        // chapter, so they are re-read once for the whole run rather than per
        // origin that happened to add something
        if outcomes.contains(where: { if case .added = $0.result { true } else { false } }) {
            await loadLanguages()
            await loadScanlators()
        }

        refreshState = .finished(outcomes)
        schedule()
    }

    private func schedule() {
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.outcomeDuration)
            guard !Task.isCancelled else { return }
            self?.refreshState = .idle
        }
    }

    // a fetch this screen started before it was closed is still running in the
    // shared unit, and its answer is owed to whoever asks. joining takes that
    // answer rather than issuing a second request - without it the rebuilt pill
    // can only show that something is happening, then vanish when it stops
    // claims the flag synchronously and then leaves: awaiting the joins here
    // would hold the observation loop open for the length of the fetch, and
    // nothing from the database would reach the screen while it waited
    private func adopt() {
        guard !adopted, !isRefreshing else { return }

        let live = refreshables.filter { refresher.isChecking(origin: $0.originId) }
        guard !live.isEmpty else { return }

        adopted = true
        Task { [weak self] in await self?.join(live) }
    }

    private func join(_ live: [Snapshot.Refreshable]) async {
        var outcomes = live.map {
            RefreshState.Outcome(id: $0.originId, name: $0.name, icon: $0.icon, result: nil)
        }
        refreshState = .running(outcomes)

        await withTaskGroup(of: (Int64, OriginRefresher.Outcome?).self) { group in
            for target in live {
                let originId = OriginRecord.ID(rawValue: target.originId)
                group.addTask { [refresher] in
                    (target.originId, await refresher.join(originId: originId))
                }
            }

            for await (originId, outcome) in group {
                guard let outcome, let index = outcomes.firstIndex(where: { $0.id == originId }) else { continue }
                outcomes[index].result = outcome
                refreshState = .running(outcomes)
            }
        }

        refreshState = .finished(outcomes)
        schedule()
    }

    // a series whose row exists but whose chapters never landed would otherwise
    // never try again - matching short-circuits before create(), which is the only
    // other caller. this is not a refresh: it fires once, and only for an origin
    // that has never been fetched at all
    // claims its flag synchronously and then leaves, for the same reason adopt()
    // does: this runs inside the observation loop, and awaiting a network fetch
    // there holds that loop open for the length of it - a cover finishing in the
    // meantime would not reach the screen until the chapters did
    // the same unit everything else calls, so a retry while a library run is
    // already checking this origin joins that fetch instead of racing it.
    // offered on every failure rather than only the retryable ones: which is
    // which is known at the throw and not stored, and four of the reasons this
    // row can print end with the words "try again"
    func retry(origin id: Int64) async {
        guard !retrying.contains(id) else { return }
        guard let target = refreshables.first(where: { $0.originId == id }) else { return }
        guard let source = registry.source(slug: target.sourceSlug) else { return }

        retrying.insert(id)
        defer { retrying.remove(id) }

        _ = await refresher.chapters(
            source: source,
            seriesSlug: target.slug,
            originId: OriginRecord.ID(rawValue: id)
        )
    }

    // the screen's own fetch, and the only automatic one a series outside the
    // library will ever get - the walk takes inLibrary = 1 and nothing else
    // reaches a row that is merely stored. so it answers two cases with one
    // condition: never fetched (.distantPast is older than any threshold) and
    // fetched long enough ago to be worth asking again.
    //
    // gated on a sourced entry because that is the journey where freshness is
    // the point: the reader is online, in a source's catalogue, and asked for
    // this series. a library-route open stays local, which is what offline-first
    // means - a series with no chapters there shows its empty state and waits to
    // be refreshed rather than fetching behind a screen nobody opened for that
    private func prime() {
        guard !primed, !isFetchingChapters else { return }
        guard case .source = entry else { return }
        guard let snapshot else { return }
        guard snapshot.chaptersFetchedDate < Date.now.addingTimeInterval(-Constants.Refresh.staleAfter) else { return }

        let targets = snapshot.refreshables
        guard !targets.isEmpty else { return }

        primed = true
        isFetchingChapters = true

        Task { [weak self, refresher, registry] in
            // every origin, not the head of the list. a stale origin and a fresh
            // one render identically, so asking one leaves the rest permanently
            // behind with nothing on screen able to say so
            await withTaskGroup(of: Void.self) { group in
                for target in targets {
                    guard let source = registry.source(slug: target.sourceSlug) else { continue }
                    group.addTask {
                        _ = await refresher.chapters(
                            source: source,
                            seriesSlug: target.slug,
                            originId: OriginRecord.ID(rawValue: target.originId)
                        )
                    }
                }
            }
            self?.isFetchingChapters = false
        }
    }

    // MARK: - Reading

    // what the reader needs for one chapter. resolved per chapter rather than from
    // the screen's own source: a merged series serves chapters from every origin,
    // and each of them belongs to a different site
    func read(_ chapter: DetailsChapters.Chapter) -> ReaderTarget? {
        guard let seriesId else { return nil }
        guard snapshot?.row(for: chapter.id) != nil else { return nil }

        return ReaderTarget(
            seriesId: seriesId,
            chapterId: ChapterRecord.ID(rawValue: chapter.id)
        )
    }

    // opening is what marks a series as read, and clean() spares anything with a
    // read date. progress itself is written by the reader
    func open(_ chapter: DetailsChapters.Chapter) async {
        guard let seriesId else { return }
        let opened = Date.now

        do {
            try await database.writer.write { db in
                // by number, so opening a chapter marks it opened whichever source
                // ends up serving it
                try ChapterRecord.apply(
                    readDate: opened,
                    toNumbers: [chapter.number],
                    in: seriesId,
                    db: db
                )

                try SeriesRecord.markRead(seriesId, at: opened, db: db)
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Open Chapter")
        }
    }

    // bulk marking is confirmed in both directions because both destroy
    // something no source can give back - unread clears every kind of progress,
    // read overwrites a partway page position with a finished chapter. counts
    // are by chapter number, which is what the reader picked; the write itself
    // fans out across every origin carrying that number
    func markRequest(read: Bool, numbers: [Double]) -> MarkRequest? {
        let unique = Set(numbers)
        guard unique.count > 1 else { return nil }

        let touched = chapters.filter { unique.contains($0.number) }
        let losing = touched.filter { read ? ($0.progress > 0 && $0.progress < 1) : $0.progress > 0 }

        return MarkRequest(
            read: read,
            numbers: Array(unique),
            scope: unique.count,
            affected: Set(losing.map(\.number)).count
        )
    }

    // deliberately leaves lastReadDate alone - marking is bookkeeping, not
    // reading, and the date is what tells a browsed series apart from one you
    // actually opened
    func mark(read: Bool, numbers: [Double]) async {
        guard let seriesId else { return }
        let numbers = Array(Set(numbers))
        guard !numbers.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                // clearing is the one write allowed to move progress backwards -
                // marking unread has to actually reach rows that were read
                try ChapterRecord.apply(
                    progress: read ? 1.0 : 0.0,
                    toNumbers: numbers,
                    in: seriesId,
                    monotonic: read,
                    db: db
                )

                // one push for the batch maximum rather than one per number.
                // unmarking lowers the watermark, which enqueue simply declines
                // to write - a tracker is never told to forget a chapter
                try SeriesTrackerRecord.enqueue(for: seriesId, in: db)
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Update Progress")
        }
    }

    // MARK: - Merge

    // with no query: top ten library series ranked by how alike their titles
    // are, scored across both sides' full title pools so a romaji copy still
    // finds its english twin. with a query: the library's own fts search decides
    // who is in, similarity only decides the order
    func loadMergeCandidates(query: String = "") async {
        guard let seriesId else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoadingMergeCandidates = true
        defer { isLoadingMergeCandidates = false }

        do {
            let (scored, rows) = try await database.reader.read { db in
                let scored = try Self.mergeMatches(for: seriesId, matching: text, in: db)
                let rows = try Self.candidates(for: scored.map(\.id), in: db)
                return (scored, rows)
            }

            // the caller re-runs this per keystroke and cancels the last one - a
            // late result must not overwrite a newer query's
            guard !Task.isCancelled else { return }

            // hydration returns rows in table order; the score decides display order
            let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            mergeCandidates = scored.compactMap { match in
                guard let row = byId[match.id.rawValue] else { return nil }
                return DetailsMerge.Candidate(
                    id: row.id,
                    title: row.title,
                    authors: row.authors,
                    synopsis: row.synopsis,
                    cover: artwork(row.cover, path: row.path),
                    referer: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.referer,
                    status: row.status,
                    publication: row.publication,
                    origins: row.origins,
                    read: row.read,
                    total: row.total,
                    score: match.score
                )
            }
        } catch {
            AppLog.shared.log("merge candidates failed - \(error)", category: "details")
            mergeCandidates = []
        }
    }

    // everything the losing series owns moves across, then its row goes. the
    // target's own preferences, status and ordering stay untouched
    func merge(into target: Int64) async {
        guard let seriesId else { return }
        let targetId = SeriesRecord.ID(rawValue: target)
        guard targetId != seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                try Self.merge(from: seriesId, to: targetId, in: db)
            }
            mergeCandidates = []
            // the observed row was just deleted, so the screen re-points at the
            // series everything now belongs to
            observe(targetId)
            AppLog.shared.log("merged series \(seriesId.rawValue) into \(targetId.rawValue)", category: "details")
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Merge Series")
            AppLog.shared.log("merge into \(target) FAILED - \(error)", category: "details")
        }
    }

    // MARK: - Writes

    // nil clears the pick, handing the choice back to origin priority
    func setPreferredCover(_ id: Int64?) async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, SeriesRecord.Columns.preferredCoverId.set(to: id))
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Set Cover")
        }
    }

    // nil clears the pick - display falls back to origin priority, which always
    // resolves to something, so clearing is safe
    func setPreferredTitle(_ id: Int64?) async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, SeriesRecord.Columns.preferredTitleId.set(to: id))
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Set Title")
        }
    }

    func setPreferredSynopsis(_ originId: Int64?) async {
        await setPreference(SeriesRecord.Columns.preferredSynopsisOriginId, to: originId)
    }

    func setPreferredMetadata(_ originId: Int64?) async {
        await setPreference(SeriesRecord.Columns.preferredMetadataOriginId, to: originId)
    }

    private func setPreference(_ column: Column, to originId: Int64?) async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, column.set(to: originId))
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Save Preference")
        }
    }

    // membership is a toggle rather than a staged edit - the section doubles as
    // the picker, and the observation reflects the write immediately
    func toggleCollection(_ id: Int64) async {
        guard let seriesId else {
            AppLog.shared.log("collection \(id) toggle skipped - no series yet", category: "details")
            return
        }
        let collectionId = CollectionRecord.ID(rawValue: id)

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                let existing = try SeriesCollectionRecord
                    .filter(SeriesCollectionRecord.Columns.seriesId == seriesId)
                    .filter(SeriesCollectionRecord.Columns.collectionId == collectionId)
                    .fetchOne(db)

                if let existing {
                    try existing.delete(db)
                    return
                }

                // appended, so a collection keeps the order the user added things
                // in. query interface rather than raw sql because "order" is a
                // reserved keyword and needs escaping
                let highest = try SeriesCollectionRecord
                    .filter(SeriesCollectionRecord.Columns.collectionId == collectionId)
                    .select(max(SeriesCollectionRecord.Columns.order), as: Int.self)
                    .fetchOne(db) ?? nil

                let next = (highest ?? -1) + 1

                var link = SeriesCollectionRecord(
                    id: nil,
                    seriesId: seriesId,
                    collectionId: collectionId,
                    order: next
                )
                try link.insert(db)
            }
            AppLog.shared.log("collection \(id) toggled for series \(seriesId.rawValue)", category: "details")
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Update Collection")
            AppLog.shared.log("collection \(id) toggle FAILED - \(error)", category: "details")
        }
    }

    // created empty, then joined - so the sheet closes on a collection that
    // already exists rather than one pending a second write
    func createCollection(name: String, description: String?, joining: Bool = true) async {
        isSaving = true
        defer { isSaving = false }

        do {
            let id = try await database.writer.write { db -> Int64 in
                var collection = CollectionRecord(name: name, description: description)
                try collection.insert(db)
                guard let id = collection.id else { throw DetailsError.missingIdentifier }
                return id.rawValue
            }

            if joining { await toggleCollection(id) }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Create Collection")
        }
    }

    // moved to the front and everything behind it shifts down, rather than parking
    // it at a negative and leaving gaps. priority has no unique constraint, but
    // keeping it dense means (priority, id) always sorts the way the list reads
    func setPrimary(_ originId: Int64) async {
        guard let seriesId else { return }
        let target = OriginRecord.ID(rawValue: originId)

        await reorder(seriesId) { ordered in
            guard let index = ordered.firstIndex(of: target) else { return ordered }
            var moved = ordered
            moved.insert(moved.remove(at: index), at: 0)
            return moved
        }
    }

    // the sheet hands back the whole arrangement, so this trusts it rather than
    // diffing - any origin it left out keeps its place at the end
    func reorderOrigins(_ ids: [Int64]) async {
        guard let seriesId else { return }
        let arranged = ids.map { OriginRecord.ID(rawValue: $0) }

        await reorder(seriesId) { ordered in
            arranged + ordered.filter { !arranged.contains($0) }
        }
    }

    // the chapters go with it by cascade, and its titles and covers stay in the
    // pool with a null originId - a name the user picked is not theirs to take
    func removeOrigin(_ originId: Int64) async {
        guard let seriesId, origins.count > 1 else { return }
        let target = OriginRecord.ID(rawValue: originId)

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try OriginRecord.filter(key: target.rawValue).deleteAll(db)
                try Self.renumber(seriesId, in: db)
            }
            AppLog.shared.log("origin \(originId) removed", category: "details")
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Remove Source")
            AppLog.shared.log("origin \(originId) remove FAILED - \(error)", category: "details")
        }
    }

    private func reorder(
        _ seriesId: SeriesRecord.ID,
        _ arrange: @escaping ([OriginRecord.ID]) -> [OriginRecord.ID]
    ) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                let ordered = try Self.ordered(seriesId, in: db)
                try Self.assign(arrange(ordered), in: db)
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Reorder Sources")
            AppLog.shared.log("origin reorder FAILED - \(error)", category: "details")
        }
    }

    // MARK: - Language priority

    // every language this series has a chapter in, in ranked order. unranked ones
    // come last, which is where best_chapter puts them too
    func loadLanguages() async {
        guard let seriesId, !isLoadingLanguages else { return }
        isLoadingLanguages = true
        defer { isLoadingLanguages = false }

        do {
            languageOrder = try await database.reader.read { db in
                try Self.languages(for: seriesId, in: db)
            }
        } catch {
            // a background load. the screen keeps what it has rather than nagging
            AppLog.shared.log("languages failed - \(error)", category: "details")
        }
    }

    // the sheet lists only languages the series actually has chapters in, so a
    // commit is a swap within the slots those languages already hold - the
    // reordered languages take each other's priorities, sorted ascending, and
    // every unlisted row keeps its place. no priority is ever minted or
    // duplicated, and the seeded relative order of absent languages survives
    func reorderLanguages(_ codes: [String]) async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                // a series from before seeding may lack rows; heal before swapping
                try SeriesLanguagePriorityRecord.seedDefaults(for: seriesId, in: db)

                let rows = try SeriesLanguagePriorityRecord
                    .filter(SeriesLanguagePriorityRecord.Columns.seriesId == seriesId)
                    .fetchAll(db)
                let byLanguage = Dictionary(uniqueKeysWithValues: rows.map { ($0.language, $0) })

                let ordered = codes.compactMap(LanguageCode.init)
                let slots = ordered.compactMap { byLanguage[$0]?.priority }.sorted()
                guard slots.count == ordered.count else { return }

                for (slot, language) in zip(slots, ordered) {
                    guard var row = byLanguage[language], row.priority != slot else { continue }
                    row.priority = slot
                    try row.update(db)
                }
            }
            await loadLanguages()
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Reorder Languages")
            AppLog.shared.log("language reorder FAILED - \(error)", category: "details")
        }
    }

    nonisolated private static func languages(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [LanguageOrder.Language] {
        // straight off the base tables, not best_chapter: a language that
        // currently wins nothing is exactly the one you came here to promote
        let sql = """
            SELECT
                c.\(ChapterRecord.Columns.language.name) AS code,
                COUNT(c.id) AS chapterCount
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            LEFT JOIN \(SeriesLanguagePriorityRecord.databaseTableName) slp
                ON slp.\(SeriesLanguagePriorityRecord.Columns.seriesId.name) = o.\(OriginRecord.Columns.seriesId.name)
                AND slp.\(SeriesLanguagePriorityRecord.Columns.language.name) = c.\(ChapterRecord.Columns.language.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            GROUP BY c.\(ChapterRecord.Columns.language.name)
            ORDER BY
                COALESCE(MIN(slp.\(SeriesLanguagePriorityRecord.Columns.priority.name)), 999) ASC,
                c.\(ChapterRecord.Columns.language.name) ASC
            """

        return try StoredLanguage
            .fetchAll(db, sql: sql, arguments: [seriesId.rawValue])
            .compactMap { row in
                guard let code = LanguageCode(rawValue: row.code) else { return nil }
                return LanguageOrder.Language(
                    id: code.rawValue,
                    flag: code.flag,
                    name: code.displayName,
                    chapterCount: row.chapterCount
                )
            }
    }

    private struct StoredLanguage: Decodable, FetchableRecord, Sendable {
        let code: String
        let chapterCount: Int
    }

    // MARK: - Scanlator priority

    // read when the sheet opens rather than with the series: it needs every
    // scanlator, not just the ones currently winning a chapter, so it cannot come
    // off the rank-1 chapter list the screen already has
    func loadScanlators() async {
        guard let seriesId, !isLoadingScanlators else { return }
        isLoadingScanlators = true
        defer { isLoadingScanlators = false }

        do {
            let rows = try await database.reader.read { db in
                try Self.scanlators(for: seriesId, in: db)
            }
            scanlatorGroups = Self.group(rows, into: origins)
        } catch {
            // a background load. the screen keeps what it has rather than nagging
            AppLog.shared.log("scanlators failed - \(error)", category: "details")
        }
    }

    // priority is stored per (origin, scanlator), so ordering is committed one
    // origin at a time. every row is written, not just moved ones - a gap in the
    // sequence would let COALESCE(priority, 999) reorder things behind the user
    func reorderScanlators(_ originId: Int64, _ ids: [Int64]) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                for (index, id) in ids.enumerated() {
                    var row = OriginScanlatorPriorityRecord(
                        originId: OriginRecord.ID(rawValue: originId),
                        scanlatorId: ScanlatorRecord.ID(rawValue: id),
                        priority: index
                    )
                    try row.upsert(db)
                }
            }
            await loadScanlators()
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Reorder Groups")
            AppLog.shared.log("scanlator reorder FAILED - \(error)", category: "details")
        }
    }

    private struct StoredScanlator: Decodable, FetchableRecord, Sendable {
        let originId: Int64
        let scanlatorId: Int64
        let name: String
        let chapterCount: Int
    }

    nonisolated private static func scanlators(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredScanlator] {
        // no best_chapter here: a scanlator that currently loses every chapter is
        // exactly the one you open this sheet to promote
        let sql = """
            SELECT
                o.id AS originId,
                s.id AS scanlatorId,
                s.\(ScanlatorRecord.Columns.name.name) AS name,
                COUNT(c.id) AS chapterCount
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            JOIN \(ScanlatorRecord.databaseTableName) s ON s.id = c.\(ChapterRecord.Columns.scanlatorId.name)
            LEFT JOIN \(OriginScanlatorPriorityRecord.databaseTableName) osp
                ON osp.\(OriginScanlatorPriorityRecord.Columns.originId.name) = o.id
                AND osp.\(OriginScanlatorPriorityRecord.Columns.scanlatorId.name) = s.id
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            GROUP BY o.id, s.id
            ORDER BY
                o.\(OriginRecord.Columns.priority.name) ASC,
                COALESCE(MIN(osp.\(OriginScanlatorPriorityRecord.Columns.priority.name)), 999) ASC,
                s.\(ScanlatorRecord.Columns.name.name) ASC
            """

        return try StoredScanlator.fetchAll(db, sql: sql, arguments: [seriesId.rawValue])
    }

    // grouped in place so the query's ordering survives - origin priority between
    // groups, scanlator priority within one
    nonisolated private static func group(
        _ rows: [StoredScanlator],
        into origins: [DetailsSources.Origin]
    ) -> [ScanlatorOrder.Origin] {
        var groups: [ScanlatorOrder.Origin] = []

        for row in rows {
            let scanlator = ScanlatorOrder.Scanlator(
                id: row.scanlatorId,
                name: row.name,
                chapterCount: row.chapterCount
            )

            if let index = groups.firstIndex(where: { $0.id == row.originId }) {
                groups[index].scanlators.append(scanlator)
            } else {
                let origin = origins.first { $0.id == row.originId }
                groups.append(
                    ScanlatorOrder.Origin(
                        id: row.originId,
                        name: origin?.name ?? "Unknown Source",
                        icon: origin?.icon,
                        scanlators: [scanlator]
                    )
                )
            }
        }

        return groups
    }

    // MARK: - Chapter visibility

    var showAllChapters: Bool { snapshot?.showAllChapters ?? false }
    var showHalfChapters: Bool { snapshot?.showHalfChapters ?? true }

    // every source's copy rather than the winner of each number. this is the one
    // setting that makes the priority sheets moot, so it overrides the half-chapter
    // filter too - a list showing everything cannot be hiding halves
    func setShowAllChapters(_ value: Bool) async {
        await setVisibility(SeriesRecord.Columns.showAllChapters, value)
    }

    func setShowHalfChapters(_ value: Bool) async {
        await setVisibility(SeriesRecord.Columns.showHalfChapters, value)
    }

    private func setVisibility(_ column: Column, _ value: Bool) async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, column.set(to: value))
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Update Visibility")
        }
    }

    func setStatus(_ value: Status) async {
        guard let seriesId, value != status else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, SeriesRecord.Columns.status.set(to: value.rawValue))
            }
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Update Status")
        }
    }

    // reports whether the write landed: adding opens the setup flow, and that
    // flow writes status and collections against a row it has to know exists
    @discardableResult
    func toggleLibrary() async -> Bool {
        guard let seriesId else { return false }

        isSaving = true
        defer { isSaving = false }

        let value = !inLibrary
        do {
            try await database.writer.write { db in
                try Self.setInLibrary(value, for: seriesId, in: db)
            }
            return true
        } catch {
            actionFailure = Failure(error, fallback: "Couldn't Update Library")
            return false
        }
    }
}

// MARK: - Types

extension DetailsViewModel {
    // one entry per origin the run is talking to, so a three-source series shows
    // three answers rather than one summary that hides which source is broken.
    // running and finished carry the same list - the difference is only whether
    // entries can still change
    enum RefreshState: Equatable {
        case idle
        case running([Outcome])
        case finished([Outcome])

        var outcomes: [Outcome] {
            switch self {
            case .idle: []
            case .running(let outcomes), .finished(let outcomes): outcomes
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

    // the source is not itself hashable, so identity comes from the slugs that
    // resolved it - which is what a navigation value has to compare on anyway
    // the reader resolves its own chapter list and page urls, so opening one
    // only needs to say which series and where to start
    struct ReaderTarget: Hashable, Identifiable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID

        var id: Int64 { chapterId.rawValue }
    }

    // scope is what the reader chose, affected is what it costs them - the two
    // diverge because marking read only overwrites chapters left partway
    struct MarkRequest: Identifiable {
        let id = UUID()
        let read: Bool
        let numbers: [Double]
        let scope: Int
        let affected: Int
    }

    struct Snapshot {
        let title: String
        let cover: URL?
        let synopsis: AttributedString?
        let authors: [String]
        let tags: [String]
        let classification: Classification?
        let publication: Publication?
        let inLibrary: Bool
        let status: Status
        let showAllChapters: Bool
        let showHalfChapters: Bool
        let readCount: Int
        let lastReadDate: Date
        let metadataFetchedDate: Date
        let chaptersFetchedDate: Date
        let referer: URL?
        let chapters: [DetailsChapters.Chapter]
        let origins: [DetailsSources.Origin]
        let covers: [DetailsCovers.Cover]
        let titles: [DetailsTitles.Title]
        let synopses: [DetailsEdit.Synopsis]
        let choices: [DetailsEdit.Metadata]
        let collections: [CollectionPicker.Item]
        let refreshables: [Refreshable]
        let links: [DetailsTracking.Link]
        let localProgress: Int

        fileprivate let rows: [StoredChapter]

        struct Refreshable: Sendable {
            let originId: Int64
            let slug: String
            let sourceSlug: String
            let name: String
            let icon: ImageResource?
        }

        fileprivate func row(for id: Int64) -> StoredChapter? {
            rows.first { $0.id == id }
        }
    }
}

private extension DetailsViewModel.Snapshot {
    init(
        _ stored: Stored,
        registry: Compositor.Registry,
        formats: [Tracker: ScoreFormat],
        artwork: (URL?, String?) -> URL?
    ) {
        let entry = stored.entry

        title = entry.title
        cover = artwork(entry.cover, entry.path)
        synopsis = entry.synopsis?.isEmpty == false ? entry.synopsis?.toAttributed() : nil
        authors = Self.split(entry.authors)
        // sources return tags in their own order, so sort for display. localized
        // standard compare is case insensitive and orders any numbers naturally
        tags = Self.split(entry.tags).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        classification = entry.classification
        publication = entry.publication
        inLibrary = entry.inLibrary
        status = stored.series.status
        showAllChapters = stored.series.showAllChapters
        showHalfChapters = stored.series.showHalfChapters
        readCount = entry.readChapterCount
        lastReadDate = entry.lastReadDate
        rows = stored.chapters

        chapters = stored.display

        origins = stored.origins.map { row in
            // three different unavailabilities, and they need different answers from
            // the user: re-enable it, re-attach it, or accept the source no longer
            // ships with the app. the source row survives all three, so only the
            // icon needs the registry - it is a compiled asset, not stored data
            let availability: DetailsSources.Origin.Availability =
                if row.disconnected { .disconnected }
                else if !row.installed { .missing }
                else if row.disabled { .disabled }
                else { .available }

            return DetailsSources.Origin(
                id: row.id,
                name: row.sourceName ?? row.sourceSlug ?? "Unknown Source",
                slug: row.slug,
                host: row.sourceBaseURL?.host() ?? row.sourceSlug ?? "",
                url: URL(string: row.url),
                icon: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.icon,
                priority: row.priority,
                chapterCount: row.chapterCount,
                fetchedDate: row.chaptersFetchedDate > .distantPast ? row.chaptersFetchedDate : nil,
                availability: availability,
                failureReason: row.fetchError,
                failedDate: row.fetchAttemptedDate > .distantPast ? row.fetchAttemptedDate : nil
            )
        }

        titles = stored.titles.map { row in
            DetailsTitles.Title(
                id: row.id,
                value: row.value,
                sourceName: row.sourceName,
                sourceIcon: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.icon,
                isPreferred: row.isPreferred
            )
        }

        collections = stored.collections.map {
            CollectionPicker.Item(id: $0.id, name: $0.name, count: $0.count, contains: $0.contains)
        }

        localProgress = stored.watermark

        links = stored.trackers.compactMap { row in
            guard let id = row.id else { return nil }
            return DetailsTracking.Link(
                id: id.rawValue,
                tracker: row.tracker,
                remoteId: row.remoteId,
                remoteTitle: row.remoteTitle,
                status: row.remoteStatus,
                progress: row.remoteProgress,
                total: row.totalChapters,
                score: row.remoteScore,
                scoreFormat: formats[row.tracker] ?? .point10,
                syncedDate: row.syncedDate,
                attemptedDate: row.attemptedDate,
                failureReason: row.syncError
            )
        }

        // an origin with no synopsis has nothing to offer, so it is not a choice
        synopses = stored.origins.compactMap { row in
            guard !row.synopsis.isEmpty else { return nil }
            return DetailsEdit.Synopsis(
                id: row.id,
                sourceName: row.sourceName ?? row.sourceSlug,
                sourceIcon: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.icon,
                text: row.synopsis,
                isPreferred: row.isSynopsis
            )
        }

        choices = stored.origins.map { row in
            DetailsEdit.Metadata(
                id: row.id,
                sourceName: row.sourceName ?? row.sourceSlug,
                sourceIcon: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.icon,
                classification: row.classification,
                publication: row.publication,
                isPreferred: row.isMetadata
            )
        }

        covers = stored.covers.map { row in
            DetailsCovers.Cover(
                id: row.id,
                url: row.url,
                local: artwork(nil, row.path),
                sourceName: row.sourceName,
                sourceIcon: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.icon,
                isPreferred: row.isPreferred
            )
        }

        #if DEBUG
        // temporary: the pool as the screen sees it, so a cover that never
        // downloads can be told apart from one that downloaded and is not being
        // pointed at. `path` nil with a preferred mark is the downloader never
        // reaching it; a path present and still no artwork is a resolve problem
        for row in stored.covers {
            AppLog.shared.log(
                "cover \(row.id)\(row.isPreferred ? " [preferred]" : "") path=\(row.path ?? "nil") url=\(row.url.absoluteString)",
                category: "covers"
            )
        }
        if stored.covers.isEmpty {
            AppLog.shared.log("no cover rows for this series", category: "covers")
        }
        #endif

        // origins are already ordered available first, and a refresh speaks to
        // every one of them that installed code can still reach - the head of the
        // list is only the one whose dates stand for the series
        refreshables = stored.origins.compactMap { row in
            guard row.installed, !row.disconnected, !row.disabled else { return nil }
            guard let slug = row.sourceSlug, let source = registry.source(slug: slug) else { return nil }
            return Refreshable(
                originId: row.id,
                slug: row.slug,
                sourceSlug: slug,
                name: row.sourceName ?? slug,
                icon: source.descriptor.icon
            )
        }
        let usable = refreshables.first.flatMap { first in
            stored.origins.first { $0.id == first.originId }
        }

        // whichever origin heads the list supplies the displayed cover, so its
        // referer is the one image requests have to carry - stored, so it outlives
        // the source being uninstalled
        referer = stored.origins.first?.sourceReferer

        let primary = usable ?? stored.origins.first
        metadataFetchedDate = primary?.metadataFetchedDate ?? .distantPast
        chaptersFetchedDate = primary?.chaptersFetchedDate ?? .distantPast
    }

    // group_concat joins with ", " and yields null rather than an empty string
    static func split(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.components(separatedBy: ", ").filter { !$0.isEmpty }
    }
}

// MARK: - Queries

extension DetailsViewModel {
    nonisolated fileprivate static func chapters(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredChapter] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(ChapterRecord.Columns.slug.name) AS slug,
                c.\(ChapterRecord.Columns.title.name) AS title,
                c.\(ChapterRecord.Columns.number.name) AS number,
                c.\(ChapterRecord.Columns.language.name) AS language,
                c.\(ChapterRecord.Columns.progress.name) AS progress,
                c.\(ChapterRecord.Columns.url.name) AS url,
                c.\(ChapterRecord.Columns.path.name) AS path,
                c.\(ChapterRecord.Columns.publishedDate.name) AS publishedDate,
                s.\(ScanlatorRecord.Columns.name.name) AS scanlator,
                o.\(OriginRecord.Columns.slug.name) AS originSlug,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(BestChapterView.databaseTableName) bc ON bc.chapterId = c.id
            JOIN \(ScanlatorRecord.databaseTableName) s ON s.id = c.\(ChapterRecord.Columns.scanlatorId.name)
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE bc.seriesId = ?
              -- rank = 1 is the deduplicated list. showAllChapters drops that
              -- filter entirely, so every source's copy of a number is a row
              AND (bc.showAllChapters = 1 OR bc.rank = 1)
              -- isVisible already folds in showAllChapters and showHalfChapters
              AND bc.isVisible = 1
            ORDER BY bc.number ASC
            """

        return try StoredChapter.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    // ordered the way best_chapter ranks them: priority first, id as the
    // deterministic tiebreak, unavailable sources last
    // the icon resolves through the registry, so a source that is no longer
    // compiled in yields nil and the row renders a placeholder
    nonisolated fileprivate static func display(
        _ rows: [StoredChapter],
        registry: Compositor.Registry
    ) -> [DetailsChapters.Chapter] {
        rows.map { row in
            let source = row.sourceSlug.flatMap { registry.source(slug: $0) }
            return DetailsChapters.Chapter(
                id: row.id,
                number: row.number,
                title: row.title,
                scanlator: row.scanlator,
                language: row.language,
                publishedDate: row.publishedDate,
                progress: row.progress,
                url: row.url,
                sourceIcon: source?.descriptor.icon,
                canRead: source != nil,
                downloaded: row.path != nil
            )
        }
    }

    nonisolated fileprivate static func origins(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredOrigin] {
        let sql = """
            SELECT
                o.id AS id,
                o.\(OriginRecord.Columns.slug.name) AS slug,
                o.\(OriginRecord.Columns.url.name) AS url,
                o.\(OriginRecord.Columns.priority.name) AS priority,
                o.\(OriginRecord.Columns.chaptersFetchedDate.name) AS chaptersFetchedDate,
                o.\(OriginRecord.Columns.metadataFetchedDate.name) AS metadataFetchedDate,
                o.\(OriginRecord.Columns.fetchAttemptedDate.name) AS fetchAttemptedDate,
                o.\(OriginRecord.Columns.fetchError.name) AS fetchError,
                o.\(OriginRecord.Columns.synopsis.name) AS synopsis,
                o.\(OriginRecord.Columns.classification.name) AS classification,
                o.\(OriginRecord.Columns.publication.name) AS publication,
                COALESCE(o.id = s.\(SeriesRecord.Columns.preferredSynopsisOriginId.name), 0) AS isSynopsis,
                COALESCE(o.id = s.\(SeriesRecord.Columns.preferredMetadataOriginId.name), 0) AS isMetadata,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                src.\(SourceRecord.Columns.baseURL.name) AS sourceBaseURL,
                src.\(SourceRecord.Columns.referer.name) AS sourceReferer,
                (o.\(OriginRecord.Columns.sourceId.name) IS NULL) AS disconnected,
                COALESCE(src.\(SourceRecord.Columns.disabled.name), 0) AS disabled,
                COALESCE(src.\(SourceRecord.Columns.installed.name), 0) AS installed,
                (
                    SELECT COUNT(*)
                    FROM \(ChapterRecord.databaseTableName) c
                    WHERE c.\(ChapterRecord.Columns.originId.name) = o.id
                ) AS chapterCount
            FROM \(OriginRecord.databaseTableName) o
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.seriesId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            ORDER BY
                (o.\(OriginRecord.Columns.sourceId.name) IS NULL OR COALESCE(src.\(SourceRecord.Columns.disabled.name), 0)) ASC,
                o.\(OriginRecord.Columns.priority.name) ASC,
                o.id ASC
            """

        return try StoredOrigin.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    // every collection, not just this series' - the picker lists all of them,
    // so a row has to know both its size and whether this series is in it
    nonisolated fileprivate static func collections(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredCollection] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(CollectionRecord.Columns.name.name) AS name,
                (SELECT COUNT(*)
                   FROM \(SeriesCollectionRecord.databaseTableName) sc
                  WHERE sc.\(SeriesCollectionRecord.Columns.collectionId.name) = c.id) AS count,
                EXISTS(SELECT 1
                         FROM \(SeriesCollectionRecord.databaseTableName) sc
                        WHERE sc.\(SeriesCollectionRecord.Columns.collectionId.name) = c.id
                          AND sc.\(SeriesCollectionRecord.Columns.seriesId.name) = ?) AS contains
            FROM \(CollectionRecord.databaseTableName) c
            ORDER BY c.\(CollectionRecord.Columns.name.name) ASC
            """

        return try StoredCollection.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    nonisolated fileprivate static func titles(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredTitle] {
        let sql = """
            SELECT
                t.id AS id,
                t.\(TitleRecord.Columns.value.name) AS value,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                COALESCE(t.id = s.\(SeriesRecord.Columns.preferredTitleId.name), 0) AS isPreferred
            FROM \(TitleRecord.databaseTableName) t
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = t.\(TitleRecord.Columns.seriesId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = t.\(TitleRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE t.\(TitleRecord.Columns.seriesId.name) = ?
            ORDER BY t.id ASC
            """

        return try StoredTitle.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    nonisolated fileprivate static func covers(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredCover] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(CoverRecord.Columns.url.name) AS url,
                c.\(CoverRecord.Columns.path.name) AS path,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                COALESCE(c.id = s.\(SeriesRecord.Columns.preferredCoverId.name), 0) AS isPreferred
            FROM \(CoverRecord.databaseTableName) c
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = c.\(CoverRecord.Columns.seriesId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(CoverRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE c.\(CoverRecord.Columns.seriesId.name) = ?
            ORDER BY c.id ASC
            """

        return try StoredCover.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    // every library series scored by its best title-pair match against this
    // one's pool. scoring runs in swift - the pools are small and sqlite has no
    // string-distance function to push it into. a query narrows membership
    // through the same fts view the library searches; the top-ten cap applies
    // only to the unqueried list, since a search already narrowed by hand
    nonisolated fileprivate static func mergeMatches(
        for seriesId: SeriesRecord.ID,
        matching query: String,
        in db: Database
    ) throws -> [(id: SeriesRecord.ID, score: Double)] {
        let own = try TitleRecord
            .select(TitleRecord.Columns.value, as: String.self)
            .filter(TitleRecord.Columns.seriesId == seriesId)
            .fetchAll(db)
        guard !own.isEmpty else { return [] }

        var sql = """
            SELECT t.\(TitleRecord.Columns.seriesId.name) AS seriesId,
                   t.\(TitleRecord.Columns.value.name) AS value
            FROM \(TitleRecord.databaseTableName) t
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = t.\(TitleRecord.Columns.seriesId.name)
            WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1 AND s.id != ?
            """
        var arguments: StatementArguments = [seriesId]

        if !query.isEmpty {
            // prefix matching, same as the library grid - results narrow as you
            // type rather than only landing on whole words
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
            sql += """

                AND s.id IN (
                    SELECT rowid FROM \(SeriesFTS5View.databaseTableName)
                    WHERE \(SeriesFTS5View.databaseTableName) MATCH ?
                )
                """
            arguments += [pattern]
        }

        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)

        var pools: [Int64: [String]] = [:]
        for row in rows {
            pools[row["seriesId"], default: []].append(row["value"])
        }

        let scored = pools
            .map { id, titles in
                let best = titles
                    .flatMap { title in own.map { Similarity.score($0, title) } }
                    .max() ?? 0
                return (id: SeriesRecord.ID(rawValue: id), score: best)
            }
            .sorted { $0.score > $1.score }

        return query.isEmpty ? Array(scored.prefix(mergeCandidateLimit)) : scored
    }

    nonisolated fileprivate static func candidates(
        for ids: [SeriesRecord.ID],
        in db: Database
    ) throws -> [StoredCandidate] {
        guard !ids.isEmpty else { return [] }

        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT
                v.\(RichfulEntryView.Columns.seriesId.name) AS id,
                v.\(RichfulEntryView.Columns.title.name) AS title,
                v.\(RichfulEntryView.Columns.authors.name) AS authors,
                v.\(RichfulEntryView.Columns.synopsis.name) AS synopsis,
                v.\(RichfulEntryView.Columns.cover.name) AS cover,
                v.\(RichfulEntryView.Columns.path.name) AS path,
                v.\(RichfulEntryView.Columns.readChapterCount.name) AS read,
                v.\(RichfulEntryView.Columns.totalChapterCount.name) AS total,
                v.\(RichfulEntryView.Columns.lastReadDate.name) AS lastReadDate,
                v.\(RichfulEntryView.Columns.addedDate.name) AS addedDate,
                v.\(RichfulEntryView.Columns.publication.name) AS publication,
                (SELECT sr.\(SeriesRecord.Columns.status.name)
                   FROM \(SeriesRecord.databaseTableName) sr
                  WHERE sr.id = v.\(RichfulEntryView.Columns.seriesId.name)) AS status,
                (SELECT COUNT(*)
                   FROM \(OriginRecord.databaseTableName) oc
                  WHERE oc.\(OriginRecord.Columns.seriesId.name) = v.\(RichfulEntryView.Columns.seriesId.name)) AS origins,
                (SELECT src.\(SourceRecord.Columns.slug.name)
                   FROM \(OriginRecord.databaseTableName) o
                   JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
                  WHERE o.\(OriginRecord.Columns.seriesId.name) = v.\(RichfulEntryView.Columns.seriesId.name)
                  ORDER BY o.\(OriginRecord.Columns.priority.name) ASC LIMIT 1) AS sourceSlug
            FROM \(RichfulEntryView.databaseTableName) v
            WHERE v.\(RichfulEntryView.Columns.seriesId.name) IN (\(placeholders))
            """

        return try StoredCandidate.fetchAll(db, sql: sql, arguments: StatementArguments(ids.map(\.rawValue)))
    }
}

// MARK: - Writes

extension DetailsViewModel {
    // into nil creates the series this origin belongs to. into an id attaches the
    // origin to a series that already exists, which is what confirming a match does
    nonisolated fileprivate static func create(
        from detail: SeriesDetail,
        sourceId: SourceRecord.ID,
        matching stubCover: URL?,
        into existing: SeriesRecord.ID?,
        in db: Database
    ) throws -> (SeriesRecord.ID, OriginRecord.ID) {
        var series = SeriesRecord()
        let seriesId: SeriesRecord.ID

        if let existing {
            seriesId = existing
        } else {
            try series.insert(db)
            guard let inserted = series.id else { throw DetailsError.missingIdentifier }
            seriesId = inserted
        }

        try SeriesLanguagePriorityRecord.seedDefaults(for: seriesId, in: db)

        let priority = try Int.fetchOne(
            db,
            sql: """
                SELECT COALESCE(MAX(\(OriginRecord.Columns.priority.name)), -1) + 1
                FROM \(OriginRecord.databaseTableName)
                WHERE \(OriginRecord.Columns.seriesId.name) = ?
                """,
            arguments: [seriesId]
        ) ?? 0

        var origin = OriginRecord(
            id: nil,
            seriesId: seriesId,
            sourceId: sourceId,
            slug: detail.slug,
            url: detail.url.absoluteString,
            synopsis: detail.synopsis,
            priority: priority,
            classification: detail.classification,
            publication: detail.publication,
            // this origin exists because a details response just arrived
            metadataFetchedDate: .now
        )
        try origin.insert(db)
        guard let originId = origin.id else { throw DetailsError.missingIdentifier }

        // the source's own title goes in first, and becomes the preferred one
        var preferredTitleId: TitleRecord.ID?
        for value in [detail.title] + detail.altTitles {
            let title = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: seriesId, originId: originId, value: value),
                in: db
            )
            if preferredTitleId == nil { preferredTitleId = title.id }
        }

        // the search result's own cover joins the pool, LAST. it used to be
        // passed in for matching and then discarded, which meant the one url in
        // this whole transaction known to work - it had just rendered on the
        // card the reader tapped - was the only one not kept. a series whose
        // details response gave a dead url therefore had a pool of exactly one
        // dead url, nothing to fall back to, and no way to ever recover.
        //
        // last rather than first, so a source whose details artwork is better
        // than its search thumbnail still wins on quality: the preference is
        // still chosen from detail.covers, and this is the rung underneath.
        //
        // it also makes primaryCover's first tier reachable for the first time -
        // that tier matches against the stub url, in a set that until now could
        // never contain it
        let pool = detail.covers + (stubCover.map { detail.covers.contains($0) ? [] : [$0] } ?? [])

        let primary = primaryCover(among: detail.covers, matching: stubCover) ?? stubCover
        var preferredCoverId: CoverRecord.ID?
        for url in pool {
            let cover = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: seriesId, originId: originId, url: url, path: nil),
                in: db
            )
            if url == primary { preferredCoverId = cover.id }
        }

        for name in detail.authors {
            let author = try AuthorRecord.findOrCreate(AuthorRecord(id: nil, name: name), in: db)
            guard let authorId = author.id else { continue }
            var link = SeriesAuthorRecord(id: nil, seriesId: seriesId, authorId: authorId)
            try link.insert(db, onConflict: .ignore)
        }

        for name in detail.tags {
            let tag = try TagRecord.findOrCreate(
                TagRecord(id: nil, normalizedName: sanitised(name), displayName: name, canonicalId: nil),
                in: db
            )
            guard let tagId = tag.id else { continue }
            var link = SeriesTagRecord(id: nil, seriesId: seriesId, tagId: tagId)
            try link.insert(db, onConflict: .ignore)
        }

        // an attached origin joins a series that already has its preferences set,
        // and taking them over would swap the display out from under the user
        guard existing == nil else { return (seriesId, originId) }

        series.preferredTitleId = preferredTitleId
        series.preferredCoverId = preferredCoverId
        series.preferredSynopsisOriginId = originId
        series.preferredMetadataOriginId = originId
        try series.update(db)

        return (seriesId, originId)
    }

    // reparent plus the two things a library row owns that a browse row does
    // not: collection memberships and read state worth propagating. collections
    // copy first while the losing row still exists; reparent then moves origins,
    // titles and covers and explicitly deletes the row; the watermark runs last
    // over the combined chapter set
    nonisolated fileprivate static func merge(
        from series: SeriesRecord.ID,
        to target: SeriesRecord.ID,
        in db: Database
    ) throws {
        try adoptCollections(from: series, to: target, in: db)
        try reparent(from: series, to: target, in: db)
        try propagateReadState(for: target, in: db)
    }

    // insert-or-ignore against the (seriesId, collectionId) unique key, so a
    // collection both sides already share stays a single membership
    nonisolated fileprivate static func adoptCollections(
        from series: SeriesRecord.ID,
        to target: SeriesRecord.ID,
        in db: Database
    ) throws {
        let links = try SeriesCollectionRecord
            .filter(SeriesCollectionRecord.Columns.seriesId == series)
            .fetchAll(db)

        for link in links {
            let highest = try SeriesCollectionRecord
                .filter(SeriesCollectionRecord.Columns.collectionId == link.collectionId)
                .select(max(SeriesCollectionRecord.Columns.order), as: Int.self)
                .fetchOne(db) ?? nil

            var adopted = SeriesCollectionRecord(
                id: nil,
                seriesId: target,
                collectionId: link.collectionId,
                order: (highest ?? -1) + 1
            )
            try adopted.insert(db, onConflict: .ignore)
        }
    }

    // attaching a source marks everything at or below the series' highest read
    // number as read; a merge makes the same promise over the union of both
    // chapter sets. monotonic, so nothing already further along moves backwards
    nonisolated fileprivate static func propagateReadState(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws {
        let sql = """
            SELECT DISTINCT c.\(ChapterRecord.Columns.number.name)
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
              AND c.\(ChapterRecord.Columns.number.name) <= (
                SELECT MAX(r.\(ChapterRecord.Columns.number.name))
                FROM \(ChapterRecord.databaseTableName) r
                JOIN \(OriginRecord.databaseTableName) ro ON ro.id = r.\(ChapterRecord.Columns.originId.name)
                WHERE ro.\(OriginRecord.Columns.seriesId.name) = ?
                  AND r.\(ChapterRecord.Columns.progress.name) >= 1
              )
            """
        let numbers = try Double.fetchAll(db, sql: sql, arguments: [seriesId, seriesId])
        try ChapterRecord.apply(progress: 1.0, toNumbers: numbers, in: seriesId, monotonic: true, db: db)

        // a merge can raise the watermark past what the service last heard, so
        // the same intent is recorded here as anywhere else reading is written
        try SeriesTrackerRecord.enqueue(for: seriesId, in: db)
    }

    // every origin the held row owns moves across, then the row itself goes. titles
    // and covers carry their origin, so they travel with it. UPDATE OR IGNORE
    // because the target may already hold an identical title or cover url
    nonisolated fileprivate static func reparent(
        from series: SeriesRecord.ID,
        to target: SeriesRecord.ID,
        in db: Database
    ) throws {
        var next = try Int.fetchOne(
            db,
            sql: """
                SELECT COALESCE(MAX(\(OriginRecord.Columns.priority.name)), -1) + 1
                FROM \(OriginRecord.databaseTableName)
                WHERE \(OriginRecord.Columns.seriesId.name) = ?
                """,
            arguments: [target]
        ) ?? 0

        let origins = try OriginRecord
            .filter(OriginRecord.Columns.seriesId == series)
            .order(OriginRecord.Columns.priority.asc, OriginRecord.Columns.id.asc)
            .fetchAll(db)

        for origin in origins {
            guard let originId = origin.id else { continue }

            try db.execute(
                sql: """
                    UPDATE \(OriginRecord.databaseTableName)
                    SET \(OriginRecord.Columns.seriesId.name) = ?, \(OriginRecord.Columns.priority.name) = ?
                    WHERE id = ?
                    """,
                arguments: [target, next, originId]
            )
            next += 1

            for table in [TitleRecord.databaseTableName, CoverRecord.databaseTableName] {
                try db.execute(
                    sql: "UPDATE OR IGNORE \(table) SET seriesId = ? WHERE originId = ?",
                    arguments: [target, originId]
                )
            }
        }

        try db.execute(
            sql: "DELETE FROM \(SeriesRecord.databaseTableName) WHERE id = ?",
            arguments: [series]
        )
    }

    // the same order the list renders in, so an index here means what it looks
    // like it means on screen
    nonisolated fileprivate static func ordered(
        _ seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [OriginRecord.ID] {
        try OriginRecord
            .select(OriginRecord.Columns.id, as: OriginRecord.ID.self)
            .filter(OriginRecord.Columns.seriesId == seriesId)
            .order(OriginRecord.Columns.priority.asc, OriginRecord.Columns.id.asc)
            .fetchAll(db)
    }

    nonisolated fileprivate static func assign(
        _ ordered: [OriginRecord.ID],
        in db: Database
    ) throws {
        for (position, id) in ordered.enumerated() {
            _ = try OriginRecord
                .filter(key: id.rawValue)
                .updateAll(db, OriginRecord.Columns.priority.set(to: position))
        }
    }

    // closes whatever gap a removal left, so priorities stay 0..n-1
    nonisolated fileprivate static func renumber(
        _ seriesId: SeriesRecord.ID,
        in db: Database
    ) throws {
        try assign(try ordered(seriesId, in: db), in: db)
    }

    // removing resets addedDate, so a series re-added later takes a fresh date
    nonisolated fileprivate static func setInLibrary(
        _ inLibrary: Bool,
        for id: SeriesRecord.ID,
        in db: Database
    ) throws {
        _ = try SeriesRecord
            .filter(key: id.rawValue)
            .updateAll(
                db,
                SeriesRecord.Columns.inLibrary.set(to: inLibrary),
                SeriesRecord.Columns.addedDate.set(to: inLibrary ? Date.now : Date.distantPast)
            )
    }

    // exact url, else the same filename ignoring extension, else the first listed
    nonisolated fileprivate static func primaryCover(among covers: [URL], matching stub: URL?) -> URL? {
        guard let stub else { return covers.first }
        if let exact = covers.first(where: { $0 == stub }) { return exact }

        let stem = stub.deletingPathExtension().lastPathComponent
        return covers.first { $0.deletingPathExtension().lastPathComponent == stem } ?? covers.first
    }

    nonisolated fileprivate static func sanitised(_ tag: String) -> String {
        tag.lowercased().replacingOccurrences(of: " ", with: "")
    }
}

private enum DetailsError: Error {
    case missingIdentifier
}

private struct Stored: Sendable {
    let series: SeriesRecord
    let entry: RichfulEntryView
    let chapters: [StoredChapter]
    let display: [DetailsChapters.Chapter]
    let origins: [StoredOrigin]
    let covers: [StoredCover]
    let titles: [StoredTitle]
    let collections: [StoredCollection]
    let trackers: [SeriesTrackerRecord]
    let watermark: Int
}

private struct StoredCandidate: Decodable, FetchableRecord, Sendable {
    let id: Int64
    let title: String
    let authors: String?
    let synopsis: String?
    let cover: URL?
    let path: String?
    let read: Int
    let total: Int
    let lastReadDate: Date
    let addedDate: Date
    let publication: Publication
    let status: Status
    let origins: Int
    let sourceSlug: String?
}

private struct StoredOrigin: Decodable, FetchableRecord, Sendable {
    let id: Int64
    let slug: String
    let url: String
    let priority: Int
    let chapterCount: Int
    let chaptersFetchedDate: Date
    let metadataFetchedDate: Date
    let fetchAttemptedDate: Date
    let fetchError: String?
    let synopsis: String
    let classification: Classification
    let publication: Publication
    let isSynopsis: Bool
    let isMetadata: Bool
    let sourceSlug: String?
    let sourceName: String?
    let sourceBaseURL: URL?
    let sourceReferer: URL?
    let disconnected: Bool
    let disabled: Bool
    let installed: Bool
}

private struct StoredCollection: Decodable, FetchableRecord, Sendable {
    let id: Int64
    let name: String
    let count: Int
    let contains: Bool
}

private struct StoredTitle: Decodable, FetchableRecord, Sendable {
    let id: Int64
    let value: String
    let sourceSlug: String?
    let sourceName: String?
    let isPreferred: Bool
}

private struct StoredCover: Decodable, FetchableRecord, Sendable {
    let id: Int64
    let url: URL
    let path: String?
    let sourceSlug: String?
    let sourceName: String?
    let isPreferred: Bool
}

private struct StoredChapter: Decodable, FetchableRecord, Sendable {
    let id: Int64
    let slug: String
    let title: String
    let number: Double
    let language: LanguageCode
    let progress: Double
    let url: URL
    let path: String?
    let publishedDate: Date
    let scanlator: String
    let originSlug: String
    let sourceSlug: String?
}

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
    private(set) var errorMessage: String?

    private var seriesId: SeriesRecord.ID?
    private var held: SeriesRecord.ID?
    private var started = false
    private var primed = false
    private var stream: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?

    private static let outcomeDuration: Duration = .seconds(3)

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
        database: DatabaseClient
    ) {
        self.entry = entry
        self.registry = registry
        self.assets = assets
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
    var synopsis: String? { snapshot?.synopsis }
    var authors: [String] { snapshot?.authors ?? [] }
    var tags: [String] { snapshot?.tags ?? [] }
    var classification: Classification? { snapshot?.classification }
    var publication: Publication? { snapshot?.publication }
    var inLibrary: Bool { snapshot?.inLibrary ?? false }
    var status: Status { snapshot?.status ?? .planning }
    var chapters: [DetailsChapters.Chapter] { snapshot?.chapters ?? [] }
    var origins: [DetailsSources.Origin] { snapshot?.origins ?? [] }
    var covers: [DetailsCovers.Cover] { snapshot?.covers ?? [] }
    var titles: [DetailsTitles.Title] { snapshot?.titles ?? [] }
    var synopses: [DetailsEdit.Synopsis] { snapshot?.synopses ?? [] }
    var metadataChoices: [DetailsEdit.Metadata] { snapshot?.choices ?? [] }
    var readCount: Int { snapshot?.readCount ?? 0 }
    var lastReadDate: Date? { snapshot.flatMap { $0.lastReadDate > .distantPast ? $0.lastReadDate : nil } }
    var lastMetadataFetch: Date? { snapshot.flatMap { $0.metadataFetchedDate > .distantPast ? $0.metadataFetchedDate : nil } }

    // an empty chapter list only means "none" once a fetch has actually landed
    var hasFetchedChapters: Bool { (snapshot?.chaptersFetchedDate ?? .distantPast) > .distantPast }

    var canToggleLibrary: Bool { seriesId != nil && !isSaving }
    var needsDisambiguation: Bool { !candidates.isEmpty }
    var isRefreshing: Bool { refreshState == .checking }
    var canRefresh: Bool { refreshTarget != nil && !isRefreshing }

    // the screen renders from the database alone, so a row is all it waits on
    var isReady: Bool { snapshot != nil && !needsDisambiguation }

    // every cover request has to carry the referer of the site that served it or
    // the host 403s. taken from the stored origin, so it still resolves for a
    // series whose source is no longer installed
    var referer: URL? { snapshot?.referer ?? opener?.descriptor.referer }

    // the section lists what this series is in; the picker needs every collection
    // so there is something to add it to
    var collections: [DetailsCollections.Item] { (snapshot?.collections ?? []).filter(\.contains) }
    var availableCollections: [DetailsCollections.Item] { snapshot?.collections ?? [] }

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
            failure = .unavailable
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
            errorMessage = String(describing: error)
            failure = .fetch(String(describing: error))
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
            errorMessage = String(describing: error)
            await settle()
        }
    }

    // MARK: - Create

    // the only path that fetches. everything else on this screen reads rows that
    // are already there
    private func create(into existing: SeriesRecord.ID?) async {
        guard let source = opener, let stub = openerStub else {
            // a library entry always carries its row id, so it never arrives here
            failure = .unavailable
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
            await fetchChapters(source: source, seriesSlug: stub.slug, originId: ids.1)
        } catch {
            failure = .fetch(String(describing: error))
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

                return Stored(
                    series: series,
                    entry: entry,
                    chapters: try Self.chapters(for: id, in: db),
                    origins: try Self.origins(for: id, in: db),
                    covers: try Self.covers(for: id, in: db),
                    titles: try Self.titles(for: id, in: db),
                    collections: try Self.collections(for: id, in: db)
                )
            }

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    guard let stored else { continue }
                    self.snapshot = Snapshot(stored, registry: registry) { remote, path in
                        self.artwork(remote, path: path)
                    }
                    await self.prime()
                }
            } catch {
                self?.errorMessage = String(describing: error)
            }
        }
    }

    // MARK: - Refresh

    // which source speaks for this series, and under what slug. a sourced entry
    // knows already; a library one takes its highest priority available origin
    private var refreshTarget: (source: Source, slug: String)? {
        if let source = opener, let stub = openerStub {
            return (source, stub.slug)
        }

        guard let primary = snapshot?.refreshable else { return nil }
        guard let source = registry.source(slug: primary.sourceSlug) else { return nil }
        return (source, primary.slug)
    }

    func refresh() async {
        guard let target = refreshTarget, !isRefreshing else { return }
        guard let originId = snapshot?.refreshable?.originId else { return }
        let origin = OriginRecord.ID(rawValue: originId)

        refreshState = .checking

        do {
            let detail = try await target.source.details(seriesSlug: target.slug)
            try await database.writer.write { db in
                try Self.update(originId: origin, from: detail, in: db)
            }
            // covers are add-only on refresh, so a refresh can introduce new ones
            if let seriesId { assets.enqueue(series: seriesId) }
        } catch {
            // metadata failing is not a reason to skip chapters - they are fetched
            // separately and are the half a refresh is usually reaching for
            errorMessage = String(describing: error)
        }

        let added = await fetchChapters(source: target.source, seriesSlug: target.slug, originId: origin)
        report(added)
    }

    func refreshChapters() async {
        guard let target = refreshTarget, !isRefreshing else { return }
        guard let originId = snapshot?.refreshable?.originId else { return }

        refreshState = .checking
        let added = await fetchChapters(
            source: target.source,
            seriesSlug: target.slug,
            originId: OriginRecord.ID(rawValue: originId)
        )
        report(added)
    }

    // the outcome replaces the spinner in place, then clears itself. cancelling
    // the previous dismissal means a second refresh restarts the three seconds
    // rather than inheriting whatever was left of the last one
    private func report(_ added: Int?) {
        guard let added else {
            refreshState = .failed
            return schedule()
        }
        refreshState = added > 0 ? .added(added) : .unchanged
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

    // the count of chapters that did not already exist, or nil when the fetch
    // threw - the outcome pill needs to tell "nothing new" from "could not check"
    @discardableResult
    private func fetchChapters(
        source: Source,
        seriesSlug: String,
        originId: OriginRecord.ID
    ) async -> Int? {
        isFetchingChapters = true
        defer { isFetchingChapters = false }

        let have = snapshot?.origins.first { $0.id == originId.rawValue }?.chapterCount ?? 0

        do {
            // nil means the source checked and nothing changed, empty means it
            // genuinely has none. both are answers, so both stamp - only a thrown
            // error leaves the list unknown, and only then does the skeleton stay
            let entries = try await source.chapters(seriesSlug: seriesSlug, have: have)
            let fetched = Date.now

            let added = try await database.writer.write { db -> Int in
                var inserted = 0
                if let entries, !entries.isEmpty {
                    inserted = try Self.upsert(entries, for: originId, in: db)
                }

                _ = try OriginRecord
                    .filter(key: originId.rawValue)
                    .updateAll(db, OriginRecord.Columns.chaptersFetchedDate.set(to: fetched))

                return inserted
            }

            AppLog.shared.log(
                "origin \(originId.rawValue) fetched \(entries?.count.description ?? "no") chapter(s), \(added) new, had \(have)",
                category: "details"
            )
            return added
        } catch {
            errorMessage = String(describing: error)
            AppLog.shared.log("origin \(originId.rawValue) chapter fetch FAILED — \(error)", category: "details")
            return nil
        }
    }

    // a series whose row exists but whose chapters never landed would otherwise
    // never try again - matching short-circuits before create(), which is the only
    // other caller. this is not a refresh: it fires once, and only for an origin
    // that has never been fetched at all
    private func prime() async {
        guard !primed, !isFetchingChapters else { return }
        guard let snapshot, snapshot.chaptersFetchedDate == .distantPast else { return }
        guard let origin = snapshot.refreshable, let target = refreshTarget else { return }

        primed = true
        await fetchChapters(
            source: target.source,
            seriesSlug: target.slug,
            originId: OriginRecord.ID(rawValue: origin.originId)
        )
    }

    // MARK: - Reading

    // what the reader needs for one chapter. resolved per chapter rather than from
    // the screen's own source: a merged series serves chapters from every origin,
    // and each of them belongs to a different site
    func read(_ chapter: DetailsChapters.Chapter) -> ReaderTarget? {
        guard let row = snapshot?.row(for: chapter.id) else { return nil }
        guard let slug = row.sourceSlug, let source = registry.source(slug: slug) else { return nil }

        return ReaderTarget(
            source: source,
            sourceSlug: slug,
            seriesSlug: row.originSlug,
            chapterSlug: row.slug,
            title: "Ch. \(chapter.number.formatted())"
        )
    }

    // opening is what marks a series as read, and clean() spares anything with a
    // read date. progress itself is written by the reader
    func open(_ chapter: DetailsChapters.Chapter) async {
        guard let seriesId else { return }
        let opened = Date.now

        do {
            try await database.writer.write { db in
                _ = try ChapterRecord
                    .filter(key: chapter.id)
                    .updateAll(db, ChapterRecord.Columns.lastReadDate.set(to: opened))

                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, SeriesRecord.Columns.lastReadDate.set(to: opened))
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // deliberately leaves lastReadDate alone - marking is bookkeeping, not
    // reading, and the date is what tells a browsed series apart from one you
    // actually opened
    func markAll(read: Bool) async {
        let ids = chapters.map(\.id)
        guard !ids.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try ChapterRecord
                    .filter(ids.contains(ChapterRecord.Columns.id))
                    .updateAll(db, ChapterRecord.Columns.progress.set(to: read ? 1.0 : 0.0))
            }
        } catch {
            errorMessage = String(describing: error)
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
            errorMessage = String(describing: error)
        }
    }

    // not optional, unlike the cover: a series always displays under some title,
    // so the pick can move but never be cleared
    func setPreferredTitle(_ id: Int64) async {
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
            errorMessage = String(describing: error)
        }
    }

    func setPreferredSynopsis(_ originId: Int64) async {
        await setPreference(SeriesRecord.Columns.preferredSynopsisOriginId, to: originId)
    }

    func setPreferredMetadata(_ originId: Int64) async {
        await setPreference(SeriesRecord.Columns.preferredMetadataOriginId, to: originId)
    }

    private func setPreference(_ column: Column, to originId: Int64) async {
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
            errorMessage = String(describing: error)
        }
    }

    // membership is a toggle rather than a staged edit - the section doubles as
    // the picker, and the observation reflects the write immediately
    func toggleCollection(_ id: Int64) async {
        guard let seriesId else {
            AppLog.shared.log("collection \(id) toggle skipped — no series yet", category: "details")
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
            errorMessage = String(describing: error)
            AppLog.shared.log("collection \(id) toggle FAILED — \(error)", category: "details")
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
            errorMessage = String(describing: error)
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
            errorMessage = String(describing: error)
            AppLog.shared.log("origin \(originId) remove FAILED — \(error)", category: "details")
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
            errorMessage = String(describing: error)
            AppLog.shared.log("origin reorder FAILED — \(error)", category: "details")
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
            errorMessage = String(describing: error)
        }
    }

    func toggleLibrary() async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        let value = !inLibrary
        do {
            try await database.writer.write { db in
                try Self.setInLibrary(value, for: seriesId, in: db)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

// MARK: - Types

extension DetailsViewModel {
    enum Failure: Equatable {
        case unavailable
        case fetch(String)
    }

    enum RefreshState: Equatable {
        case idle
        case checking
        case added(Int)
        case unchanged
        case failed
    }

    // the source is not itself hashable, so identity comes from the slugs that
    // resolved it - which is what a navigation value has to compare on anyway
    struct ReaderTarget: Hashable, Identifiable {
        let source: Source
        let sourceSlug: String
        let seriesSlug: String
        let chapterSlug: String
        let title: String

        var id: String { "\(sourceSlug)/\(seriesSlug)/\(chapterSlug)" }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    struct Snapshot {
        let title: String
        let cover: URL?
        let synopsis: String?
        let authors: [String]
        let tags: [String]
        let classification: Classification?
        let publication: Publication?
        let inLibrary: Bool
        let status: Status
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
        let collections: [DetailsCollections.Item]
        let refreshable: Refreshable?

        fileprivate let rows: [StoredChapter]

        struct Refreshable {
            let originId: Int64
            let slug: String
            let sourceSlug: String
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
        artwork: (URL?, String?) -> URL?
    ) {
        let entry = stored.entry

        title = entry.title
        cover = artwork(entry.cover, entry.path)
        synopsis = entry.synopsis?.isEmpty == false ? entry.synopsis : nil
        authors = Self.split(entry.authors)
        // sources return tags in their own order, so sort for display. localized
        // standard compare is case insensitive and orders any numbers naturally
        tags = Self.split(entry.tags).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        classification = entry.classification
        publication = entry.publication
        inLibrary = entry.inLibrary
        status = stored.series.status
        readCount = entry.readChapterCount
        lastReadDate = entry.lastReadDate
        rows = stored.chapters

        chapters = stored.chapters.map { row in
            // the icon resolves through the registry, so a source that is no longer
            // compiled in yields nil and the row renders a placeholder
            let source = row.sourceSlug.flatMap { registry.source(slug: $0) }
            return DetailsChapters.Chapter(
                id: row.id,
                number: row.number,
                title: row.title,
                scanlator: row.scanlator,
                language: row.language,
                publishedDate: row.publishedDate,
                progress: row.progress,
                sourceIcon: source?.descriptor.icon,
                canRead: source != nil
            )
        }

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
                host: row.sourceBaseURL?.host() ?? row.sourceSlug ?? "",
                url: URL(string: row.url),
                icon: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.icon,
                priority: row.priority,
                chapterCount: row.chapterCount,
                fetchedDate: row.chaptersFetchedDate > .distantPast ? row.chaptersFetchedDate : nil,
                availability: availability
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
            DetailsCollections.Item(id: $0.id, name: $0.name, count: $0.count, contains: $0.contains)
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

        // origins are already ordered available first, so the first one still backed
        // by installed code is the one refresh speaks to
        let usable = stored.origins.first { row in
            guard row.installed, !row.disconnected, !row.disabled else { return false }
            return row.sourceSlug.flatMap { registry.source(slug: $0) } != nil
        }
        refreshable = usable.flatMap { row in
            row.sourceSlug.map { Refreshable(originId: row.id, slug: row.slug, sourceSlug: $0) }
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
              AND bc.rank = 1
              AND bc.isVisible = 1
            ORDER BY bc.number ASC
            """

        return try StoredChapter.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    // ordered the way best_chapter ranks them: priority first, id as the
    // deterministic tiebreak, unavailable sources last
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
                o.\(OriginRecord.Columns.synopsis.name) AS synopsis,
                o.\(OriginRecord.Columns.classification.name) AS classification,
                o.\(OriginRecord.Columns.publication.name) AS publication,
                (o.id = s.\(SeriesRecord.Columns.preferredSynopsisOriginId.name)) AS isSynopsis,
                (o.id = s.\(SeriesRecord.Columns.preferredMetadataOriginId.name)) AS isMetadata,
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

    // every collection, not just this series' - the section doubles as the picker,
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
                (t.id = s.\(SeriesRecord.Columns.preferredTitleId.name)) AS isPreferred
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
                (c.id = s.\(SeriesRecord.Columns.preferredCoverId.name)) AS isPreferred
            FROM \(CoverRecord.databaseTableName) c
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = c.\(CoverRecord.Columns.seriesId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(CoverRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE c.\(CoverRecord.Columns.seriesId.name) = ?
            ORDER BY c.id ASC
            """

        return try StoredCover.fetchAll(db, sql: sql, arguments: [seriesId])
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

        let primary = primaryCover(among: detail.covers, matching: stubCover)
        var preferredCoverId: CoverRecord.ID?
        for url in detail.covers {
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

    // metadata a refresh is allowed to overwrite. titles and covers are add-only,
    // so a pick the user made can never be taken away by a later fetch
    nonisolated fileprivate static func update(
        originId: OriginRecord.ID,
        from detail: SeriesDetail,
        in db: Database
    ) throws {
        guard var origin = try OriginRecord.fetchOne(db, key: originId.rawValue) else { return }

        _ = try origin.updateChanges(db) {
            $0.synopsis = detail.synopsis
            $0.classification = detail.classification
            $0.publication = detail.publication
            $0.metadataFetchedDate = .now
        }

        for value in [detail.title] + detail.altTitles {
            _ = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: origin.seriesId, originId: originId, value: value),
                in: db
            )
        }

        for url in detail.covers {
            _ = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: origin.seriesId, originId: originId, url: url, path: nil),
                in: db
            )
        }
    }

    // chapters arrive independently of the rest of a series, so this runs on its
    // own and is safe to repeat. progress and lastReadDate are never overwritten
    @discardableResult
    nonisolated fileprivate static func upsert(
        _ entries: [ChapterEntry],
        for originId: OriginRecord.ID,
        in db: Database
    ) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        var inserted = 0

        var scanlators: [String: ScanlatorRecord.ID] = [:]
        for entry in entries where scanlators[entry.scanlator] == nil {
            let scanlator = try ScanlatorRecord.findOrCreate(
                ScanlatorRecord(id: nil, name: entry.scanlator),
                in: db
            )
            guard let scanlatorId = scanlator.id else { continue }
            scanlators[entry.scanlator] = scanlatorId

            // order of first appearance, and only when absent - a refresh must not
            // discard an ordering the user has since set
            var priority = OriginScanlatorPriorityRecord(
                originId: originId,
                scanlatorId: scanlatorId,
                priority: scanlators.count - 1
            )
            try priority.insert(db, onConflict: .ignore)
        }

        let existing = try ChapterRecord
            .filter(ChapterRecord.Columns.originId == originId)
            .fetchAll(db)
        let bySlug = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in entries {
            guard let scanlatorId = scanlators[entry.scanlator] else { continue }

            if var current = bySlug[entry.slug] {
                // diffed against the stored encoding, so a source that returned
                // nothing new issues no UPDATE and wakes no observation
                _ = try current.updateChanges(db) {
                    $0.title = entry.title
                    $0.number = entry.number
                    $0.publishedDate = entry.publishedDate
                    $0.language = entry.language
                    $0.url = entry.url
                }
            } else {
                var chapter = ChapterRecord(
                    id: nil,
                    originId: originId,
                    scanlatorId: scanlatorId,
                    slug: entry.slug,
                    title: entry.title,
                    number: entry.number,
                    publishedDate: entry.publishedDate,
                    language: entry.language,
                    progress: 0,
                    lastReadDate: nil,
                    url: entry.url,
                    path: nil
                )
                try chapter.insert(db)
                inserted += 1
            }
        }

        return inserted
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
    let origins: [StoredOrigin]
    let covers: [StoredCover]
    let titles: [StoredTitle]
    let collections: [StoredCollection]
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
    let publishedDate: Date
    let scanlator: String
    let originSlug: String
    let sourceSlug: String?
}

//
//  LibraryViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB
import Observation
import SwiftUI
import Tagged

@MainActor
@Observable
final class LibraryViewModel {
    private let database: DatabaseClient
    private let assets: Compositor.Assets
    private let registry: Compositor.Registry
    private let privacy: Compositor.Privacy

    private(set) var entries: [Entry] = []
    private(set) var collections: [Collection] = []

    private(set) var tags: [Option<TagRecord.ID>] = []
    private(set) var sources: [Option<SourceRecord.ID>] = []
    private(set) var trackers: [TrackerFilter] = []

    private var tagMembership: [SeriesRecord.ID: Set<TagRecord.ID>] = [:]
    private var sourceMembership: [SeriesRecord.ID: Set<SourceRecord.ID>] = [:]
    private var trackerMembership: [SeriesRecord.ID: Set<Tracker>] = [:]
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var failure: Failure?

    var searchText = ""

    var sort: LibrarySort = Preferences.Default.librarySort {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Preferences.Key.librarySort)
        }
    }

    var ascending = Preferences.Default.librarySortAscending {
        didSet {
            UserDefaults.standard.set(ascending, forKey: Preferences.Key.librarySortAscending)
        }
    }

    // includes members not currently in the library - the intersection happens at
    // read time so this stays correct if a series leaves and rejoins
    private var membership: [CollectionRecord.ID: Set<SeriesRecord.ID>] = [:]

    // nil is "no query", empty is "a query that matched nothing" - collapsing the
    // two would show the whole library the moment a search failed
    private var matches: Set<SeriesRecord.ID>?

    init(
        database: DatabaseClient, assets: Compositor.Assets, registry: Compositor.Registry,
        privacy: Compositor.Privacy
    ) {
        self.database = database
        self.assets = assets
        self.registry = registry
        self.privacy = privacy

        let defaults = UserDefaults.standard

        if let stored = defaults.string(forKey: Preferences.Key.librarySort),
            let sort = LibrarySort(rawValue: stored)
        {
            self.sort = sort
        }

        if defaults.object(forKey: Preferences.Key.librarySortAscending) != nil {
            ascending = defaults.bool(forKey: Preferences.Key.librarySortAscending)
        }

        // a stored filter naming a case that no longer exists decodes to nothing,
        // not a decode failure that would leave the library unfilterable
        if let data = defaults.data(forKey: Preferences.Key.libraryFilter),
            let stored = try? JSONDecoder().decode(LibraryFilter.self, from: data)
        {
            filter = stored
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    var filter = LibraryFilter() {
        didSet {
            guard let data = try? JSONEncoder().encode(filter) else { return }
            UserDefaults.standard.set(data, forKey: Preferences.Key.libraryFilter)
        }
    }

    var isFiltered: Bool {
        !searchText.isEmpty || filter.isActive
    }

    var filtered: [Entry] {
        var result = entries

        if let matches {
            result = result.filter { matches.contains($0.id) }
        }

        if filter.isActive {
            let asOf = Date.now
            result = result.filter {
                filter.matches($0, asOf: asOf)
                    && filter.matches(
                        tagIDs: tagMembership[$0.id] ?? [],
                        sourceIDs: sourceMembership[$0.id] ?? [],
                        linked: trackerMembership[$0.id] ?? []
                    )
            }
        }

        return sort.sort(result, ascending: ascending)
    }

    // every collection a matching entry belongs to gets its own section - a
    // series in two collections is two rows, not deduplicated, since each
    // section is its own view onto the library. an entry in none lands in
    // Uncategorised instead of being dropped, so nothing is ever unreachable
    // from the hopper. sliced from the already-sorted filtered list rather
    // than re-sorted per section, since filtering preserves relative order
    var sections: [Section] {
        let base = filtered
        guard !base.isEmpty else { return [] }

        var result: [Section] = []

        let uncategorized = base.filter { entry in
            !membership.values.contains { $0.contains(entry.id) }
        }
        if !uncategorized.isEmpty {
            result.append(Section(id: .uncategorized, name: "Uncategorised", entries: uncategorized))
        }

        for collection in collections {
            let members = membership[collection.id] ?? []
            let matched = base.filter { members.contains($0.id) }
            guard !matched.isEmpty else { continue }
            let locked = collection.requiresFaceId && !privacy.isUnlocked(collection.id)
            result.append(
                Section(
                    id: .collection(collection.id), name: collection.name, entries: matched,
                    isLocked: locked))
        }

        return result
    }

    // a series in any still-locked collection blurs wherever it's shown -
    // that locked collection's own section never renders its entries (the
    // gate takes over instead), so by construction this only ever shows up
    // under a *different* section. clears once every locked collection the
    // series belongs to has been unlocked this session, not on the first
    var blurredSeriesIds: Set<SeriesRecord.ID> {
        collections
            .filter { $0.requiresFaceId && !privacy.isUnlocked($0.id) }
            .reduce(into: Set<SeriesRecord.ID>()) { result, collection in
                result.formUnion(membership[collection.id] ?? [])
            }
    }

    // MARK: Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // excluded in the query, not trimmed after - the filter vocabularies below
        // are built from these same rows, so a hidden series must not leak into
        // the tag/source filter options
        let adultSlugs = AdultGate.slugs(in: registry)

        do {
            let rows = try await database.reader.read { db in
                let excluded = try AdultGate.excluded(slugs: adultSlugs, in: db)

                return
                    try EntryView
                    .filter(EntryView.Columns.inLibrary == true)
                    .filter(!excluded.contains(EntryView.Columns.seriesId))
                    .order(EntryView.Columns.addedDate.desc)
                    .fetchAll(db)
            }

            entries = rows.map {
                Entry(
                    id: SeriesRecord.ID(rawValue: $0.seriesId),
                    title: $0.title,
                    cover: assets.local(for: $0.path) ?? $0.cover,
                    unreadCount: $0.unreadCount,
                    status: $0.status,
                    publication: $0.publication,
                    classification: $0.classification,
                    addedDate: $0.addedDate,
                    updatedDate: $0.updatedDate,
                    lastReadDate: $0.lastReadDate
                )
            }
            failure = nil
            await loadVocabularies()
        } catch {
            failure = Failure(error, fallback: "Couldn't Load Library")
            AppLog.shared.log("library load failed - \(error)", level: .error, category: "library")
        }

        await loadCollections()
    }

    // pivoted in memory rather than joined per filter change - the library is
    // bounded by what you own, so one pass here is cheaper than a query per filter
    private func loadVocabularies() async {
        let library = Set(entries.map(\.id))
        guard !library.isEmpty else {
            tags = []
            sources = []
            trackers = []
            tagMembership = [:]
            sourceMembership = [:]
            trackerMembership = [:]
            return
        }

        do {
            let (tagRows, tagLinks, sourceRows, origins, links) = try await database.reader.read {
                db in
                (
                    try TagRecord.fetchAll(db),
                    try SeriesTagRecord.fetchAll(db),
                    try SourceRecord.fetchAll(db),
                    try OriginRecord.fetchAll(db),
                    try SeriesTrackerRecord.fetchAll(db)
                )
            }

            let owned = tagLinks.filter { library.contains($0.seriesId) }
            tagMembership = Dictionary(grouping: owned, by: \.seriesId)
                .mapValues { Set($0.map(\.tagId)) }

            let usedTags = Set(owned.map(\.tagId))
            tags =
                tagRows
                .compactMap { tag in
                    guard let id = tag.id, usedTags.contains(id) else { return nil }
                    return Option(id: id, name: tag.displayName)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let ownedOrigins = origins.filter { library.contains($0.seriesId) }

            sourceMembership = Dictionary(grouping: ownedOrigins, by: \.seriesId)
                .mapValues { group in
                    Set(group.map { $0.sourceId ?? LibraryFilter.detachedSource })
                }

            let used = Set(sourceMembership.values.flatMap { $0 })
            var options =
                sourceRows
                .compactMap { source -> Option<SourceRecord.ID>? in
                    guard let id = source.id, used.contains(id) else { return nil }
                    return Option(
                        id: id,
                        name: source.name,
                        artwork: registry.source(slug: source.slug)?.descriptor.icon
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            // always appended, even when nothing is disconnected - an option shown
            // only once the problem exists could never confirm the problem's absence
            options.append(Option(id: LibraryFilter.detachedSource, name: "Disconnected"))

            sources = options

            let ownedLinks = links.filter { library.contains($0.seriesId) }
            trackerMembership = Dictionary(grouping: ownedLinks, by: \.seriesId)
                .mapValues { Set($0.map(\.tracker)) }

            // all-or-nothing, unlike tags and sources - a service nothing is
            // linked to still needs its own chip so "linked here" and "linked
            // nowhere" are both askable
            trackers = trackerMembership.isEmpty ? [] : TrackerFilter.ordered
        } catch {
            AppLog.shared.log(
                "library vocabularies failed - \(error)", level: .error, category: "library")
        }
    }

    func loadCollections() async {
        do {
            let (records, links) = try await database.reader.read { db in
                (
                    try CollectionRecord
                        .order(CollectionRecord.Columns.name.asc)
                        .fetchAll(db),
                    try SeriesCollectionRecord.fetchAll(db)
                )
            }

            membership = Dictionary(grouping: links, by: \.collectionId)
                .mapValues { Set($0.map(\.seriesId)) }

            // against the library, not the raw membership count - membership
            // includes series that have since left the library
            let library = Set(entries.map(\.id))
            collections = records.compactMap { record in
                guard let id = record.id else { return nil }
                return Collection(
                    id: id,
                    name: record.name,
                    count: membership[id]?.intersection(library).count ?? 0,
                    requiresFaceId: record.requiresFaceId
                )
            }
        } catch {
            AppLog.shared.log(
                "collections load failed - \(error)", level: .error, category: "library")
        }
    }

    // MATCH against fts5, which also indexes origin synopses and tags - an
    // in-memory title compare would silently search less than advertised
    func search() async {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            withAnimation(.smooth) { matches = nil }
            return
        }

        do {
            let found = try await database.reader.read { db -> Set<SeriesRecord.ID> in
                guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return [] }

                let ids = try Int64.fetchAll(
                    db,
                    sql: """
                        SELECT rowid FROM \(SeriesFTS5View.databaseTableName)
                        WHERE \(SeriesFTS5View.databaseTableName) MATCH ?
                        """, arguments: [pattern])

                return Set(ids.map { SeriesRecord.ID(rawValue: $0) })
            }

            // the caller cancels the previous task on every keystroke - a late
            // result must not overwrite a newer query's
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { matches = found }
        } catch {
            AppLog.shared.log(
                "library search failed - \(error)", level: .error, category: "library")
            withAnimation(.smooth) { matches = [] }
        }
    }

    // MARK: Writes

    func createCollection(name: String, description: String?) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                var collection = CollectionRecord(name: name, description: description)
                try collection.insert(db)
            }
            await loadCollections()
        } catch {
            failure = Failure(error, fallback: "Couldn't Load Library")
            AppLog.shared.log(
                "collection create failed - \(error)", level: .error, category: "library")
        }
    }

}

extension LibraryViewModel {
    struct Entry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let unreadCount: Int
        let status: Status
        let publication: Publication?
        let classification: Classification?
        let addedDate: Date
        let updatedDate: Date
        let lastReadDate: Date
    }

    struct Option<Key: Hashable>: Identifiable, Hashable {
        let id: Key
        let name: String
        var artwork: ImageResource? = nil
    }

    struct Collection: Identifiable, Hashable {
        let id: CollectionRecord.ID
        let name: String
        let count: Int
        let requiresFaceId: Bool
    }

    enum SectionID: Hashable {
        case uncategorized
        case collection(CollectionRecord.ID)
    }

    struct Section: Identifiable, Hashable {
        let id: SectionID
        let name: String
        let entries: [Entry]
        // entries stay populated even when locked, so the gate can still
        // report "N series" - the view chooses whether to render them
        var isLocked: Bool = false
    }
}

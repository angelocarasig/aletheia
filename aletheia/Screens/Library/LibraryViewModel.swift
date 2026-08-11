//
//  LibraryViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation
// for withAnimation only - the search result arrives from a task, so nothing in
// the view is in a position to wrap the mutation that reflows the grid
import SwiftUI

@MainActor
@Observable
final class LibraryViewModel {
    private let database: DatabaseClient
    private let assets: Compositor.Assets
    // sources are code-defined, so their artwork comes from the registry rather
    // than from the row
    private let registry: Compositor.Registry

    private(set) var entries: [Entry] = []
    private(set) var collections: [Collection] = []

    // only what the library actually carries - offering a tag no owned series has
    // is an option that can only ever return nothing
    private(set) var tags: [Option<TagRecord.ID>] = []
    private(set) var sources: [Option<SourceRecord.ID>] = []
    // empty when nothing in the library is linked, which is what hides the group
    // rather than offering three chips that can only return the whole library or
    // none of it
    private(set) var trackers: [TrackerFilter] = []

    private var tagMembership: [SeriesRecord.ID: Set<TagRecord.ID>] = [:]
    private var sourceMembership: [SeriesRecord.ID: Set<SourceRecord.ID>] = [:]
    private var trackerMembership: [SeriesRecord.ID: Set<Tracker>] = [:]
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var failure: Failure?

    // a collection is a subset of the library, not a place - selecting one filters
    // the grid in place rather than pushing anywhere. single-select on purpose:
    // a chip's count reads as "how many of what I am looking at are in here",
    // which only makes sense against one
    var selectedCollection: CollectionRecord.ID?

    var searchText = ""

    // written straight back to defaults: an order you picked and lost on the next
    // launch is a decision the app threw away
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

    // every collection's members, including series not in the library - the grid
    // intersects them away on its own, and a raw map stays correct if a series
    // leaves and rejoins the library
    private var membership: [CollectionRecord.ID: Set<SeriesRecord.ID>] = [:]

    // nil is "no query", empty is "a query that matched nothing" - collapsing the
    // two would show the whole library the moment a search failed
    private var matches: Set<SeriesRecord.ID>?

    init(database: DatabaseClient, assets: Compositor.Assets, registry: Compositor.Registry) {
        self.database = database
        self.assets = assets
        self.registry = registry

        let defaults = UserDefaults.standard

        if let stored = defaults.string(forKey: Preferences.Key.librarySort),
           let sort = LibrarySort(rawValue: stored) {
            self.sort = sort
        }

        if defaults.object(forKey: Preferences.Key.librarySortAscending) != nil {
            ascending = defaults.bool(forKey: Preferences.Key.librarySortAscending)
        }

        // a stored filter naming a case that no longer exists decodes to nothing
        // rather than throwing the whole library into an unfilterable state
        if let data = defaults.data(forKey: Preferences.Key.libraryFilter),
           let stored = try? JSONDecoder().decode(LibraryFilter.self, from: data) {
            filter = stored
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    // the navigation title is the collection picker's own label, so it has to say
    // which collection you are in - a title that always reads "Library" makes the
    // menu chevron look decorative
    var title: String {
        guard let selectedCollection,
              let collection = collections.first(where: { $0.id == selectedCollection })
        else { return "Library" }

        return collection.name
    }

    var filter = LibraryFilter() {
        didSet {
            guard let data = try? JSONEncoder().encode(filter) else { return }
            UserDefaults.standard.set(data, forKey: Preferences.Key.libraryFilter)
        }
    }

    var isFiltered: Bool {
        selectedCollection != nil || !searchText.isEmpty || filter.isActive
    }

    // both narrowings are set intersections against ids, so order does not matter
    // and neither re-reads the database
    var filtered: [Entry] {
        var result = entries

        if let selectedCollection {
            let members = membership[selectedCollection] ?? []
            result = result.filter { members.contains($0.id) }
        }

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

    // MARK: Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // the exclusion rides in the query rather than trimming the result, so the
        // filter vocabularies below are built from the same rows the grid draws -
        // a hidden series must not put its tags and sources in the filter sheet
        let adultSlugs = AdultGate.slugs(in: registry)

        do {
            let rows = try await database.reader.read { db in
                let excluded = try AdultGate.excluded(slugs: adultSlugs, in: db)

                return try EntryView
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
            AppLog.shared.log("library load failed - \(error)", category: "library")
        }

        await loadCollections()
    }

    // the two filter groups that are relationships rather than columns. read in
    // one pass and pivoted in memory: the alternative is a join per filter change,
    // and the library is bounded by what you own
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
            let (tagRows, tagLinks, sourceRows, origins, links) = try await database.reader.read { db in
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
            tags = tagRows
                .compactMap { tag in
                    guard let id = tag.id, usedTags.contains(id) else { return nil }
                    return Option(id: id, name: tag.displayName)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let ownedOrigins = origins.filter { library.contains($0.seriesId) }

            // a disconnected origin still says something about the series - it is
            // the one you can no longer refresh - so it maps to a reserved id
            // rather than being dropped
            sourceMembership = Dictionary(grouping: ownedOrigins, by: \.seriesId)
                .mapValues { group in
                    Set(group.map { $0.sourceId ?? LibraryFilter.detachedSource })
                }

            let used = Set(sourceMembership.values.flatMap { $0 })
            var options = sourceRows
                .compactMap { source -> Option<SourceRecord.ID>? in
                    guard let id = source.id, used.contains(id) else { return nil }
                    return Option(
                        id: id,
                        name: source.name,
                        artwork: registry.source(slug: source.slug)?.descriptor.icon
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            // last, always: it is a state rather than a source, and sorting it
            // among the names would put it under D. shown even when nothing is
            // disconnected - it is how you check, and an option that appears only
            // once the problem exists cannot be used to confirm it does not
            options.append(Option(id: LibraryFilter.detachedSource, name: "Disconnected"))

            sources = options

            let ownedLinks = links.filter { library.contains($0.seriesId) }
            trackerMembership = Dictionary(grouping: ownedLinks, by: \.seriesId)
                .mapValues { Set($0.map(\.tracker)) }

            // the whole group, or none of it. a service nothing is linked to
            // still earns its chip once anything is - the question "which of
            // these are on AniList and which are on neither" needs both sides
            // present to be askable
            trackers = trackerMembership.isEmpty ? [] : TrackerFilter.ordered
        } catch {
            AppLog.shared.log("library vocabularies failed - \(error)", category: "library")
        }
    }

    // separate from the grid read: collections change on their own schedule, and
    // creating one has to refresh the chips without re-reading every series
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

            // the count is what the chip will actually show you, so it is measured
            // against the library rather than the raw membership row count
            let library = Set(entries.map(\.id))
            collections = records.compactMap { record in
                guard let id = record.id else { return nil }
                return Collection(
                    id: id,
                    name: record.name,
                    count: membership[id]?.intersection(library).count ?? 0
                )
            }
        } catch {
            AppLog.shared.log("collections load failed - \(error)", category: "library")
        }
    }

    // one MATCH against the fts5 view, which already indexes every title, every
    // origin's synopsis and every tag - the grid's own title is only one of them,
    // so an in-memory compare would silently search less than it claims to
    func search() async {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            withAnimation(.smooth) { matches = nil }
            return
        }

        do {
            let found = try await database.reader.read { db -> Set<SeriesRecord.ID> in
                // prefix matching, so results narrow as you type rather than only
                // landing on whole words
                guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return [] }

                let ids = try Int64.fetchAll(db, sql: """
                    SELECT rowid FROM \(SeriesFTS5View.databaseTableName)
                    WHERE \(SeriesFTS5View.databaseTableName) MATCH ?
                    """, arguments: [pattern])

                return Set(ids.map { SeriesRecord.ID(rawValue: $0) })
            }

            // the caller re-runs this on every keystroke and cancels the last one:
            // a late result must not overwrite a newer query's
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { matches = found }
        } catch {
            AppLog.shared.log("library search failed - \(error)", category: "library")
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
            AppLog.shared.log("collection create failed - \(error)", category: "library")
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

    // a filter option that is a row somewhere rather than an enum case - the id is
    // what gets stored, the name is only ever displayed
    struct Option<Key: Hashable>: Identifiable, Hashable {
        let id: Key
        let name: String
        // the source's own artwork, resolved from the registry. nil for anything
        // that is a value rather than a thing
        var artwork: ImageResource? = nil
    }

    // the id is typed, so a chip selection compares against it directly and no
    // caller has to unwrap
    struct Collection: Identifiable, Hashable {
        let id: CollectionRecord.ID
        let name: String
        let count: Int
    }
}

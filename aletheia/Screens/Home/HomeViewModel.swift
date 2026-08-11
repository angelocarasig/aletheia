//
//  HomeViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let database: DatabaseClient
    private let assets: Compositor.Assets
    private let registry: Compositor.Registry

    private(set) var snapshot: Snapshot?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    // hidden from the continue rail until read again - the value is the moment
    // of dismissal, so a later lastReadDate resurrects the series
    private var dismissed: [SeriesRecord.ID: Date]

    private enum Rule {
        static let window: TimeInterval = 30 * 24 * 60 * 60
        static let continueLimit = 10
        static let continueBatch = 20
        static let addedLimit = 12
        // a tease that admits it is one. twelve rows was a slice pretending to
        // be the whole list, and it buried every section under it
        static let updateLimit = 3
        // short on purpose. a resume surface stops being glanceable somewhere
        // around six rows, and these two sit under a rail that has already
        // answered the question for most visits
        static let shelfLimit = 4
        // the window the two shelves are drawn from before they are split and
        // capped. wide enough that a library with a long tail still fills them
        static let shelfBatch = 60
    }

    init(database: DatabaseClient, assets: Compositor.Assets, registry: Compositor.Registry) {
        self.database = database
        self.assets = assets
        self.registry = registry

        if let data = UserDefaults.standard.data(forKey: Preferences.Key.homeDismissed),
           let stored = try? JSONDecoder().decode([Int64: Date].self, from: data) {
            dismissed = Dictionary(uniqueKeysWithValues: stored.map { (SeriesRecord.ID(rawValue: $0.key), $0.value) })
        } else {
            dismissed = [:]
        }
    }

    var continueReading: [ContinueEntry] { snapshot?.continueReading ?? [] }

    var recentlyAdded: [AddedEntry] { snapshot?.recentlyAdded ?? [] }

    var updates: [UpdateEntry] { snapshot?.updates ?? [] }

    var stalled: [ShelfEntry] { snapshot?.stalled ?? [] }

    var waiting: [ShelfEntry] { snapshot?.waiting ?? [] }

    var failingSources: Int { snapshot?.failingSources ?? 0 }
    var failingTrackers: Int { snapshot?.failingTrackers ?? 0 }

    var isEmpty: Bool {
        snapshot != nil && continueReading.isEmpty && updates.isEmpty && recentlyAdded.isEmpty
    }

    // the hidden set is part of what the query walks, so hiding one restarts the
    // observation and the rail refills from behind it rather than losing a slot
    func dismiss(_ id: SeriesRecord.ID) {
        dismissed[id] = .now
        let raw = Dictionary(uniqueKeysWithValues: dismissed.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Preferences.Key.homeDismissed)
        }
        stream?.cancel()
        stream = nil
        observe()
    }

    // MARK: Observation

    func observe() {
        guard stream == nil else { return }
        // captured once - an observation re-runs on every write and dates
        // computed inside it would slide mid-session (inject asOf, never Date()
        // in a query - the metrics rule)
        let asOf = Date.now
        let cutoff = asOf.addingTimeInterval(-Rule.window)

        // while the bypass is off, adult-only sources do not exist here - not on
        // the rails, not in the numbers behind them
        let adultSlugs = AdultGate.slugs(in: registry)

        let hidden = Dictionary(uniqueKeysWithValues: dismissed.map { ($0.key.rawValue, $0.value) })

        stream = Task { [weak self, database] in
            let observation = ValueObservation
                .tracking { db in
                    try Self.stored(
                        cutoff: cutoff,
                        adultSlugs: adultSlugs,
                        hidden: hidden,
                        in: db
                    )
                }
                .removeDuplicates()

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.snapshot = Snapshot(stored, assets: self.assets)
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Home")
                AppLog.shared.log("home observation failed - \(error)", category: "home")
            }
        }
    }

    func retry() {
        stream?.cancel()
        stream = nil
        failure = nil
        observe()
    }

    // MARK: Query

    fileprivate struct Stored: Equatable, Sendable {
        var continueRows: [ContinueRow]
        var updateRows: [UpdateRow]
        var addedRows: [EntryRow]
        var stalledRows: [ContinueRow]
        var waitingRows: [ContinueRow]
        var failingSources: Int
        var failingTrackers: Int
    }

    // a series and the chapters that arrived for it after you owned it. the
    // grouping is the point - "Series - 3 new chapters" is one row where three
    // chapter rows would be three
    struct UpdateRow: Equatable, Sendable {
        let entry: EntryRow
        let count: Int
        let latest: Date
        let target: ContinueTarget
    }

    struct EntryRow: Equatable, Sendable {
        let seriesId: Int64
        let title: String
        let cover: URL?
        let path: String?
        let unreadCount: Int
        let lastReadDate: Date
        let addedDate: Date
        let adult: Bool

        init(_ entry: EntryView) {
            seriesId = entry.seriesId
            title = entry.title
            cover = entry.cover
            path = entry.path
            unreadCount = entry.unreadCount
            lastReadDate = entry.lastReadDate
            addedDate = entry.addedDate
            // derived from Classification rather than a source's per-item flag,
            // so this is wider than a search stub's: Explicit folds erotica in
            // with pornography, and disk carries nothing narrower
            adult = entry.classification == .Explicit
        }
    }

    fileprivate struct ContinueRow: Equatable, Sendable {
        let entry: EntryRow
        let target: ContinueTarget
    }


    nonisolated private static func stored(
        cutoff: Date,
        adultSlugs: [String],
        hidden: [Int64: Date],
        in db: Database
    ) throws -> Stored {
        let excluded = try AdultGate.excluded(slugs: adultSlugs, in: db)

        // the exclusion rides in the query rather than trimming the result, so
        // the limit counts rows the rail can actually show
        let library = EntryView
            .filter(EntryView.Columns.inLibrary == true)
            .filter(!excluded.contains(EntryView.Columns.seriesId))

        let added = try library
            .order(EntryView.Columns.addedDate.desc)
            .limit(Rule.addedLimit)
            .fetchAll(db)

        let continueRows = try continuing(from: library, cutoff: cutoff, hidden: hidden, in: db)
        let (stalled, waiting) = try shelves(from: library, cutoff: cutoff, in: db)

        return Stored(
            continueRows: continueRows,
            updateRows: try updating(excluded: excluded, limit: Rule.updateLimit, in: db),
            addedRows: added.map { EntryRow($0) },
            stalledRows: stalled,
            waitingRows: waiting,
            failingSources: try failing(excluded: excluded, in: db),
            failingTrackers: try failingLinks(excluded: excluded, in: db)
        )
    }

    // what arrived while you were away, which is the question every reader in
    // the ecosystem opens their app to answer and the one this screen could not.
    //
    // the discriminator is `c.addedDate > s.addedDate`: chapters that landed
    // AFTER the series was yours. without it, adding a 400-chapter series posts
    // 400 updates - those are a backlog, not news, and the backlog is what
    // Recently Added is for.
    //
    // ranked through best_chapter so a series carried by three sources counts a
    // chapter once, and filtered to unread so a row never says "3 new" about
    // three you have already read
    nonisolated static func updating(
        excluded: Set<Int64>,
        limit: Int,
        in db: Database
    ) throws -> [UpdateRow] {
        let sql = """
            SELECT
                bc.seriesId AS seriesId,
                COUNT(*) AS count,
                MAX(c.\(ChapterRecord.Columns.addedDate.name)) AS latest
            FROM \(BestChapterView.databaseTableName) bc
            JOIN \(ChapterRecord.databaseTableName) c ON c.id = bc.chapterId
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = bc.seriesId
            WHERE bc.rank = 1
              AND (bc.showHalfChapters = 1 OR bc.number = CAST(bc.number AS INTEGER))
              AND s.\(SeriesRecord.Columns.inLibrary.name) = 1
              AND c.\(ChapterRecord.Columns.addedDate.name) > s.\(SeriesRecord.Columns.addedDate.name)
              AND c.\(ChapterRecord.Columns.progress.name) < 1.0
            GROUP BY bc.seriesId
            ORDER BY latest DESC
            LIMIT \(limit + excluded.count)
            """

        let grouped = try Row.fetchAll(db, sql: sql).compactMap { row -> (Int64, Int, Date)? in
            let id: Int64 = row["seriesId"]
            guard !excluded.contains(id) else { return nil }
            return (id, row["count"], row["latest"])
        }
        guard !grouped.isEmpty else { return [] }

        let ids = grouped.map { $0.0 }
        let entries = try EntryView
            .filter(ids.contains(EntryView.Columns.seriesId))
            .fetchAll(db)
            .reduce(into: [Int64: EntryView]()) { $0[$1.seriesId] = $1 }

        // the same resolver Continue Reading uses, so tapping an update opens
        // the chapter rather than a screen about the chapter
        let targets = try ContinueTarget.resolve(for: ids, in: db)

        return grouped.prefix(limit).compactMap { id, count, latest in
            guard let entry = entries[id], let target = targets[id] else { return nil }
            return UpdateRow(entry: EntryRow(entry), count: count, latest: latest, target: target)
        }
    }

    // two things still thin a page after SQL has had its say: a series the
    // reader hid, and one whose chapters are all finished (no target). so the
    // walk pages backwards through recency until the rail is full or the window
    // runs out, rather than trimming a single page and showing the remainder
    nonisolated private static func continuing(
        from library: QueryInterfaceRequest<EntryView>,
        cutoff: Date,
        hidden: [Int64: Date],
        in db: Database
    ) throws -> [ContinueRow] {
        var rows: [ContinueRow] = []
        var offset = 0

        while rows.count < Rule.continueLimit {
            let page = try library
                .filter(EntryView.Columns.lastReadDate >= cutoff)
                .order(EntryView.Columns.lastReadDate.desc)
                .limit(Rule.continueBatch, offset: offset)
                .fetchAll(db)

            guard !page.isEmpty else { break }
            offset += page.count

            let visible = page.filter { entry in
                guard let since = hidden[entry.seriesId] else { return true }
                return entry.lastReadDate > since
            }
            let targets = try ContinueTarget.resolve(for: visible.map(\.seriesId), in: db)

            rows += visible.compactMap { entry in
                targets[entry.seriesId].map { ContinueRow(entry: EntryRow(entry), target: $0) }
            }

            guard page.count == Rule.continueBatch else { break }
        }

        return Array(rows.prefix(Rule.continueLimit))
    }

    // the two shelves under the rail, and they are one query because they are one
    // partition. every library series sits in exactly one of three places:
    //
    //   read inside the window  -> Continue Reading, the rail
    //   fell out, mid-chapter   -> Pick Back Up
    //   fell out, between them  -> Waiting For You
    //
    // the cutoff is the rail's own, so nothing can be in the rail and a shelf at
    // once, and ContinueTarget already draws the second line for free: .resume
    // means the reader stopped inside a chapter, .start means they finished one
    // cleanly and chapters piled up behind it. no series appears twice, which is
    // the whole reason these are not two independent filters
    nonisolated private static func shelves(
        from library: QueryInterfaceRequest<EntryView>,
        cutoff: Date,
        in db: Database
    ) throws -> (stalled: [ContinueRow], waiting: [ContinueRow]) {
        // never read at all is not "fell behind" - it is a series you added and
        // have not started, which Recently Added used to carry and nothing on
        // this screen claims any more
        let cold = try library
            .filter(EntryView.Columns.lastReadDate < cutoff)
            .filter(EntryView.Columns.lastReadDate > Date.distantPast)
            .order(EntryView.Columns.lastReadDate.desc)
            .limit(Rule.shelfBatch)
            .fetchAll(db)

        guard !cold.isEmpty else { return ([], []) }

        let targets = try ContinueTarget.resolve(for: cold.map(\.seriesId), in: db)

        var stalled: [ContinueRow] = []
        var waiting: [ContinueRow] = []

        for entry in cold {
            // no target means every chapter is finished. that is caught up, not
            // waiting, and it belongs on neither shelf
            guard let target = targets[entry.seriesId] else { continue }
            let row = ContinueRow(entry: EntryRow(entry), target: target)

            switch target {
            case .resume: stalled.append(row)
            case .start where entry.unreadCount > 0: waiting.append(row)
            case .start: continue
            }
        }

        // most recently abandoned first: the one you stopped last is the one you
        // still half-remember, which is what makes it the cheapest to re-enter
        stalled = Array(stalled.prefix(Rule.shelfLimit))
        // biggest pile first, because the question this shelf answers is "what
        // have I fallen furthest behind on", not "what is oldest"
        waiting = Array(
            waiting
                .sorted { $0.entry.unreadCount > $1.entry.unreadCount }
                .prefix(Rule.shelfLimit)
        )

        return (stalled, waiting)
    }

    // a source that dies quietly takes its series' new chapters with it and says
    // nothing, so it is found weeks later wondering why a favourite went silent.
    // counted by source rather than by origin because that is what the banner
    // claims - the screen behind it breaks the same failures down per series
    nonisolated private static func failing(
        excluded: Set<Int64>,
        in db: Database
    ) throws -> Int {
        let exclusion = excluded.isEmpty
            ? ""
            : "AND o.\(OriginRecord.Columns.seriesId.name) NOT IN (\(excluded.map(String.init).joined(separator: ", ")))"

        return try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(DISTINCT o.\(OriginRecord.Columns.sourceId.name))
                FROM \(OriginRecord.databaseTableName) o
                JOIN \(EntryView.databaseTableName) e
                  ON e.\(EntryView.Columns.seriesId.name) = o.\(OriginRecord.Columns.seriesId.name)
                WHERE o.\(OriginRecord.Columns.fetchError.name) IS NOT NULL
                  AND e.\(EntryView.Columns.inLibrary.name) = 1
                  \(exclusion)
                """
        ) ?? 0
    }

    // counted by SERIES, not by service - the two services are at most two, so a
    // count of them says almost nothing, where "four series are not syncing" is
    // the size of the problem. the dead-account case is not this: it is one fact
    // about an account and Activity names it directly
    nonisolated private static func failingLinks(
        excluded: Set<Int64>,
        in db: Database
    ) throws -> Int {
        let exclusion = excluded.isEmpty
            ? ""
            : "AND t.\(SeriesTrackerRecord.Columns.seriesId.name) NOT IN (\(excluded.map(String.init).joined(separator: ", ")))"

        return try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(DISTINCT t.\(SeriesTrackerRecord.Columns.seriesId.name))
                FROM \(SeriesTrackerRecord.databaseTableName) t
                JOIN \(EntryView.databaseTableName) e
                  ON e.\(EntryView.Columns.seriesId.name) = t.\(SeriesTrackerRecord.Columns.seriesId.name)
                WHERE t.\(SeriesTrackerRecord.Columns.syncError.name) IS NOT NULL
                  AND e.\(EntryView.Columns.inLibrary.name) = 1
                  \(exclusion)
                """
        ) ?? 0
    }

}

// MARK: - Snapshot

extension HomeViewModel {
    struct Snapshot: Equatable {
        let continueReading: [ContinueEntry]
        let updates: [UpdateEntry]
        let recentlyAdded: [AddedEntry]
        let stalled: [ShelfEntry]
        let waiting: [ShelfEntry]
        let failingSources: Int
        let failingTrackers: Int

        #if DEBUG
        init(
            continueReading: [ContinueEntry],
            updates: [UpdateEntry],
            recentlyAdded: [AddedEntry],
            stalled: [ShelfEntry] = [],
            waiting: [ShelfEntry] = [],
            failingSources: Int = 0,
            failingTrackers: Int = 0
        ) {
            self.continueReading = continueReading
            self.updates = updates
            self.recentlyAdded = recentlyAdded
            self.stalled = stalled
            self.waiting = waiting
            self.failingSources = failingSources
            self.failingTrackers = failingTrackers
        }
        #endif

        fileprivate init(_ stored: Stored, assets: Compositor.Assets) {
            failingSources = stored.failingSources
            failingTrackers = stored.failingTrackers
            updates = stored.updateRows.map {
                UpdateEntry(
                    id: SeriesRecord.ID(rawValue: $0.entry.seriesId),
                    title: $0.entry.title,
                    cover: assets.local(for: $0.entry.path) ?? $0.entry.cover,
                    count: $0.count,
                    latest: $0.latest,
                    target: $0.target,
                    adult: $0.entry.adult
                )
            }
            continueReading = stored.continueRows.map {
                ContinueEntry(
                    id: SeriesRecord.ID(rawValue: $0.entry.seriesId),
                    title: $0.entry.title,
                    cover: assets.local(for: $0.entry.path) ?? $0.entry.cover,
                    unreadCount: $0.entry.unreadCount,
                    lastReadDate: $0.entry.lastReadDate,
                    target: $0.target,
                    adult: $0.entry.adult
                )
            }
            recentlyAdded = stored.addedRows.map {
                AddedEntry(
                    id: SeriesRecord.ID(rawValue: $0.seriesId),
                    title: $0.title,
                    cover: assets.local(for: $0.path) ?? $0.cover,
                    unreadCount: $0.unreadCount,
                    addedDate: $0.addedDate,
                    adult: $0.adult
                )
            }
            stalled = stored.stalledRows.map { ShelfEntry($0, assets: assets) }
            waiting = stored.waitingRows.map { ShelfEntry($0, assets: assets) }
        }
    }

    struct ContinueEntry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let unreadCount: Int
        let lastReadDate: Date
        let target: ContinueTarget
        let adult: Bool
    }

    // one per series, never one per chapter: a reader wants to know which of
    // their series moved, and by how much - not to scroll a chapter log
    struct UpdateEntry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let count: Int
        let latest: Date
        let target: ContinueTarget
        let adult: Bool
    }

    // one row on either shelf. the two differ by what the second line says, not
    // by what they hold, so they share a type - and the caller picks the line
    struct ShelfEntry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let unreadCount: Int
        let target: ContinueTarget
        let adult: Bool

        #if DEBUG
        init(
            id: SeriesRecord.ID,
            title: String,
            cover: URL? = nil,
            unreadCount: Int,
            target: ContinueTarget,
            adult: Bool = false
        ) {
            self.id = id
            self.title = title
            self.cover = cover
            self.unreadCount = unreadCount
            self.target = target
            self.adult = adult
        }
        #endif

        fileprivate init(_ row: ContinueRow, assets: Compositor.Assets) {
            id = SeriesRecord.ID(rawValue: row.entry.seriesId)
            title = row.entry.title
            cover = assets.local(for: row.entry.path) ?? row.entry.cover
            unreadCount = row.entry.unreadCount
            target = row.target
            adult = row.entry.adult
        }
    }

    struct AddedEntry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let unreadCount: Int
        let addedDate: Date
        let adult: Bool
    }
}

// MARK: - Preview

#if DEBUG
extension HomeViewModel {
    // a model already holding its answer. observe() is never called, so nothing
    // reads a database and every phase is reachable by what is handed in here
    static func preview(
        snapshot: Snapshot? = nil,
        failure: Failure? = nil
    ) -> HomeViewModel {
        // the pieces directly rather than a whole Compositor - building that
        // constructs every source, and a preview has no use for one
        let database = DatabaseClient.preview
        let registry = Compositor.Registry(sources: [], database: database)
        let model = HomeViewModel(
            database: database,
            assets: Compositor.Assets(database: database, registry: registry, network: NetworkService()),
            registry: registry
        )
        model.snapshot = snapshot
        model.failure = failure
        return model
    }
}
#endif

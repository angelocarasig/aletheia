//
//  HomeViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Observation
import Tagged

@MainActor
@Observable
final class HomeViewModel {
    private let database: DatabaseClient
    private let assets: Compositor.Assets
    private let registry: Compositor.Registry

    private(set) var snapshot: Snapshot?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    // value is the dismissal date, not lastReadDate - a later lastReadDate
    // resurrects the series
    private var dismissed: [SeriesRecord.ID: Date]

    private enum Rule {
        static let window: TimeInterval = 30 * 24 * 60 * 60
        static let continueLimit = 10
        static let continueBatch = 20
        static let addedLimit = 12
        static let updateLimit = 5
        static let shelfLimit = 4
        static let shelfBatch = 60
    }

    init(database: DatabaseClient, assets: Compositor.Assets, registry: Compositor.Registry) {
        self.database = database
        self.assets = assets
        self.registry = registry

        if let data = UserDefaults.standard.data(forKey: Preferences.Key.homeDismissed),
            let stored = try? JSONDecoder().decode([Int64: Date].self, from: data)
        {
            dismissed = Dictionary(
                uniqueKeysWithValues: stored.map { (SeriesRecord.ID(rawValue: $0.key), $0.value) })
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

    // hidden is snapshotted once per observe() call, so a new dismissal needs a
    // restart to take effect and refill the rail from behind it
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
        // never Date() inside the tracking closure - it re-runs on every write
        // and a date computed there would slide mid-session
        let asOf = Date.now
        let cutoff = asOf.addingTimeInterval(-Rule.window)

        let adultSlugs = AdultGate.slugs(in: registry)

        let hidden = Dictionary(uniqueKeysWithValues: dismissed.map { ($0.key.rawValue, $0.value) })

        stream = Task { [weak self, database] in
            let observation =
                ValueObservation
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
                AppLog.shared.log(
                    "home observation failed - \(error)", level: .error, category: "home")
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

        let library =
            EntryView
            .filter(EntryView.Columns.inLibrary == true)
            .filter(!excluded.contains(EntryView.Columns.seriesId))

        let added =
            try library
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

    // new = c.publishedDate > s.addedDate, not addedDate/created-today: a
    // backfilled chapter landing today isn't news, it was published whenever
    // the source says. bc.rank = 1 dedupes a series carried by multiple sources
    nonisolated static func updating(
        excluded: Set<Int64>,
        limit: Int,
        in db: Database
    ) throws -> [UpdateRow] {
        let sql = """
            SELECT
                bc.seriesId AS seriesId,
                COUNT(*) AS count,
                MAX(c.\(ChapterRecord.Columns.publishedDate.name)) AS latest
            FROM \(BestChapterView.databaseTableName) bc
            JOIN \(ChapterRecord.databaseTableName) c ON c.id = bc.chapterId
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = bc.seriesId
            WHERE bc.rank = 1
              AND (bc.showHalfChapters = 1 OR bc.number = CAST(bc.number AS INTEGER))
              AND s.\(SeriesRecord.Columns.inLibrary.name) = 1
              AND c.\(ChapterRecord.Columns.publishedDate.name) > s.\(SeriesRecord.Columns.addedDate.name)
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
        let entries =
            try EntryView
            .filter(ids.contains(EntryView.Columns.seriesId))
            .fetchAll(db)
            .reduce(into: [Int64: EntryView]()) { $0[$1.seriesId] = $1 }

        let targets = try ContinueTarget.resolve(for: ids, in: db)

        return grouped.prefix(limit).compactMap { id, count, latest in
            guard let entry = entries[id], let target = targets[id] else { return nil }
            return UpdateRow(entry: EntryRow(entry), count: count, latest: latest, target: target)
        }
    }

    // hidden series and no-target (fully read) series can still shrink a page
    // below continueLimit after the SQL fetch, so this walks pages until the
    // rail is full or the window runs out, rather than trimming a single page
    nonisolated private static func continuing(
        from library: QueryInterfaceRequest<EntryView>,
        cutoff: Date,
        hidden: [Int64: Date],
        in db: Database
    ) throws -> [ContinueRow] {
        var rows: [ContinueRow] = []
        var offset = 0

        while rows.count < Rule.continueLimit {
            let page =
                try library
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

    // three mutually exclusive states per library series, split on the rail's
    // own cutoff so nothing is in the rail and a shelf at once: read within the
    // window -> rail, fell out mid-chapter -> stalled, fell out cleanly with
    // unread piled up -> waiting
    nonisolated private static func shelves(
        from library: QueryInterfaceRequest<EntryView>,
        cutoff: Date,
        in db: Database
    ) throws -> (stalled: [ContinueRow], waiting: [ContinueRow]) {
        // lastReadDate == .distantPast means never read - excluded here, that's
        // Recently Added's territory, not a shelf
        let cold =
            try library
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
            // nil target means every chapter is read - caught up, not on either shelf
            guard let target = targets[entry.seriesId] else { continue }
            let row = ContinueRow(entry: EntryRow(entry), target: target)

            switch target {
            case .resume: stalled.append(row)
            case .start where entry.unreadCount > 0: waiting.append(row)
            case .start: continue
            }
        }

        stalled = Array(stalled.prefix(Rule.shelfLimit))
        waiting = Array(
            waiting
                .sorted { $0.entry.unreadCount > $1.entry.unreadCount }
                .prefix(Rule.shelfLimit)
        )

        return (stalled, waiting)
    }

    nonisolated private static func failing(
        excluded: Set<Int64>,
        in db: Database
    ) throws -> Int {
        let exclusion =
            excluded.isEmpty
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

    nonisolated private static func failingLinks(
        excluded: Set<Int64>,
        in db: Database
    ) throws -> Int {
        let exclusion =
            excluded.isEmpty
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

    struct UpdateEntry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let count: Int
        let latest: Date
        let target: ContinueTarget
        let adult: Bool
    }

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
        static func preview(
            snapshot: Snapshot? = nil,
            failure: Failure? = nil
        ) -> HomeViewModel {
            let database = DatabaseClient.preview
            let registry = Compositor.Registry(sources: [], database: database)
            let model = HomeViewModel(
                database: database,
                assets: Compositor.Assets(
                    database: database, registry: registry, network: NetworkService()),
                registry: registry
            )
            model.snapshot = snapshot
            model.failure = failure
            return model
        }
    }
#endif

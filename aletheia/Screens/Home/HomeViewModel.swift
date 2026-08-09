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

    // which window the tiles count over. the rails are unaffected - continuing
    // and recently added are recency facts, not measurements
    private(set) var range: StatRange

    private enum Rule {
        static let window: TimeInterval = 30 * 24 * 60 * 60
        static let continueLimit = 10
        static let continueBatch = 20
        static let addedLimit = 12
        static let sessionLimit = 5
    }

    init(database: DatabaseClient, assets: Compositor.Assets, registry: Compositor.Registry) {
        self.database = database
        self.assets = assets
        self.registry = registry

        range = UserDefaults.standard.string(forKey: Preferences.Key.homeStatRange)
            .flatMap(StatRange.init(rawValue:)) ?? Preferences.Default.homeStatRange

        if let data = UserDefaults.standard.data(forKey: Preferences.Key.homeDismissed),
           let stored = try? JSONDecoder().decode([Int64: Date].self, from: data) {
            dismissed = Dictionary(uniqueKeysWithValues: stored.map { (SeriesRecord.ID(rawValue: $0.key), $0.value) })
        } else {
            dismissed = [:]
        }
    }

    var continueReading: [ContinueEntry] { snapshot?.continueReading ?? [] }

    var recentlyAdded: [AddedEntry] { snapshot?.recentlyAdded ?? [] }

    var sessions: [ReadingSessionEntry] { snapshot?.sessions ?? [] }

    var stats: StatTiles? { snapshot?.stats }

    var isEmpty: Bool {
        snapshot != nil && continueReading.isEmpty && recentlyAdded.isEmpty
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

    // the window is baked into the query, so switching restarts the observation
    // rather than refiltering in memory. the current snapshot stays on screen
    // until the new one lands, which keeps the phase on content
    func select(_ range: StatRange) {
        guard range != self.range else { return }
        self.range = range
        UserDefaults.standard.set(range.rawValue, forKey: Preferences.Key.homeStatRange)
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
        let sinceKey = range.sinceKey(from: asOf)

        // adultOnly is a descriptor fact the database cannot see, so the slugs
        // are resolved here and the exclusion rides into the query. while the
        // bypass is off, adult-only sources do not exist anywhere - including
        // on Home's rails and in its numbers
        let adultSlugs = UserDefaults.standard.bool(forKey: Preferences.Key.bypassAdultSources)
            ? []
            : registry.sources.filter(\.descriptor.adultOnly).map(\.descriptor.slug)

        let hidden = Dictionary(uniqueKeysWithValues: dismissed.map { ($0.key.rawValue, $0.value) })

        stream = Task { [weak self, database] in
            let observation = ValueObservation
                .tracking { db in
                    try Self.stored(
                        cutoff: cutoff,
                        sinceKey: sinceKey,
                        asOf: asOf,
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
                AppLog.shared.log("home observation failed — \(error)", category: "home")
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
        var addedRows: [EntryRow]
        var sessions: [ReadingSessionEntry]
        var stats: StatTiles
    }

    struct StatTiles: Equatable, Sendable {
        let chaptersInRange: Int
        let secondsInRange: Int
        let currentRun: Int

        // all zero means nothing worth a tile - absence is the signal, the
        // strip hides rather than showing a row of noughts
        var isEmpty: Bool {
            chaptersInRange == 0 && secondsInRange == 0 && currentRun == 0
        }
    }

    fileprivate struct EntryRow: Equatable, Sendable {
        let seriesId: Int64
        let title: String
        let cover: URL?
        let path: String?
        let unreadCount: Int
        let lastReadDate: Date
        let addedDate: Date

        init(_ entry: EntryView) {
            seriesId = entry.seriesId
            title = entry.title
            cover = entry.cover
            path = entry.path
            unreadCount = entry.unreadCount
            lastReadDate = entry.lastReadDate
            addedDate = entry.addedDate
        }
    }

    fileprivate struct ContinueRow: Equatable, Sendable {
        let entry: EntryRow
        let target: ContinueTarget
    }


    nonisolated private static func stored(
        cutoff: Date,
        sinceKey: Int,
        asOf: Date,
        adultSlugs: [String],
        hidden: [Int64: Date],
        in db: Database
    ) throws -> Stored {
        let excluded = try excludedSeries(adultSlugs: adultSlugs, in: db)

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

        return Stored(
            continueRows: continueRows,
            addedRows: added.map { EntryRow($0) },
            // the same window the tiles count over - a list under a number that
            // disagrees with it is worse than no list
            sessions: try ReadingSessionEntry.fetch(
                sinceKey: sinceKey,
                excluded: excluded,
                limit: Rule.sessionLimit,
                in: db
            ),
            stats: try stats(sinceKey: sinceKey, asOf: asOf, excluded: excluded, in: db)
        )
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

    // series reachable only through an adult-only source. the descriptor fact
    // lives in code, so the slugs arrive from the registry and the set is
    // resolved here - empty while no such source ships or the bypass is on
    nonisolated private static func excludedSeries(
        adultSlugs: [String],
        in db: Database
    ) throws -> Set<Int64> {
        guard !adultSlugs.isEmpty else { return [] }

        let marks = adultSlugs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT DISTINCT o.\(OriginRecord.Columns.seriesId.name)
            FROM \(OriginRecord.databaseTableName) o
            JOIN \(SourceRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE s.\(SourceRecord.Columns.slug.name) IN (\(marks))
            """
        return Set(try Int64.fetchAll(db, sql: sql, arguments: StatementArguments(adultSlugs)))
    }

    nonisolated private static func stats(
        sinceKey: Int,
        asOf: Date,
        excluded: Set<Int64>,
        in db: Database
    ) throws -> StatTiles {
        let exclusion = excluded.isEmpty
            ? ""
            : "AND seriesId NOT IN (\(excluded.map(String.init).joined(separator: ", ")))"

        let chapters = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(ReadingEventRecord.databaseTableName)
                WHERE \(ReadingEventRecord.Columns.kind.name) = ?
                  AND \(ReadingEventRecord.Columns.localDayKey.name) >= ?
                  \(exclusion)
                """,
            arguments: [ReadingEventRecord.Kind.chapterCompleted.rawValue, sinceKey]
        ) ?? 0

        let seconds = try Int.fetchOne(
            db,
            sql: """
                SELECT IFNULL(SUM(
                    strftime('%s', \(ReadingSessionRecord.Columns.endedDate.name))
                    - strftime('%s', \(ReadingSessionRecord.Columns.startedDate.name))
                ), 0)
                FROM \(ReadingSessionRecord.databaseTableName)
                WHERE \(ReadingSessionRecord.Columns.localDayKey.name) >= ?
                  \(exclusion)
                """,
            arguments: [sinceKey]
        ) ?? 0

        let days = try Int.fetchAll(
            db,
            sql: """
                SELECT DISTINCT \(ReadingEventRecord.Columns.localDayKey.name)
                FROM \(ReadingEventRecord.databaseTableName) WHERE 1 \(exclusion)
                UNION
                SELECT DISTINCT \(ReadingSessionRecord.Columns.localDayKey.name)
                FROM \(ReadingSessionRecord.databaseTableName) WHERE 1 \(exclusion)
                """
        )

        return StatTiles(
            chaptersInRange: chapters,
            secondsInRange: seconds,
            currentRun: ReadingStreak.current(days: Set(days), asOf: asOf)
        )
    }

}

// MARK: - Snapshot

extension HomeViewModel {
    struct Snapshot: Equatable {
        let continueReading: [ContinueEntry]
        let recentlyAdded: [AddedEntry]
        let sessions: [ReadingSessionEntry]
        let stats: StatTiles

        #if DEBUG
        init(
            continueReading: [ContinueEntry],
            recentlyAdded: [AddedEntry],
            sessions: [ReadingSessionEntry],
            stats: StatTiles
        ) {
            self.continueReading = continueReading
            self.recentlyAdded = recentlyAdded
            self.sessions = sessions
            self.stats = stats
        }
        #endif

        fileprivate init(_ stored: Stored, assets: Compositor.Assets) {
            stats = stored.stats
            sessions = stored.sessions
            continueReading = stored.continueRows.map {
                ContinueEntry(
                    id: SeriesRecord.ID(rawValue: $0.entry.seriesId),
                    title: $0.entry.title,
                    cover: assets.local(for: $0.entry.path) ?? $0.entry.cover,
                    unreadCount: $0.entry.unreadCount,
                    lastReadDate: $0.entry.lastReadDate,
                    target: $0.target
                )
            }
            recentlyAdded = stored.addedRows.map {
                AddedEntry(
                    id: SeriesRecord.ID(rawValue: $0.seriesId),
                    title: $0.title,
                    cover: assets.local(for: $0.path) ?? $0.cover,
                    unreadCount: $0.unreadCount,
                    addedDate: $0.addedDate
                )
            }
        }
    }

    struct ContinueEntry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let unreadCount: Int
        let lastReadDate: Date
        let target: ContinueTarget
    }

    struct AddedEntry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let unreadCount: Int
        let addedDate: Date
    }
}

// MARK: - Preview

#if DEBUG
extension HomeViewModel {
    // a model already holding its answer. observe() is never called, so nothing
    // reads a database and every phase is reachable by what is handed in here
    static func preview(
        snapshot: Snapshot? = nil,
        failure: Failure? = nil,
        range: StatRange = .week
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
        model.range = range
        return model
    }
}
#endif

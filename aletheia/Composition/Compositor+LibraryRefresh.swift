//
//  Compositor+LibraryRefresh.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation

extension Compositor {
    // the walk: every library series in scope, through the same per-origin unit
    // a Details pull-to-refresh calls. it owns the live numbers the Activity tab
    // renders and the background task reports, and nothing else - results are
    // the chapter rows themselves, and what survives a relaunch is the columns.
    // see docs/features/background-activity.md 6.5
    @MainActor
    @Observable
    final class LibraryRefresh {
        private let database: DatabaseClient
        private let registry: Registry
        private let refresher: Refresh
        private let log: AppLog

        private(set) var scope: String?
        private(set) var current: String?
        private(set) var completed = 0
        private(set) var total = 0
        private(set) var failures = 0

        // which series are being checked right now, so a library card can ask
        // about itself by id rather than reading the whole run and redrawing
        // every cell on every tick
        private(set) var active: Set<Int64> = []

        @ObservationIgnored private var run: Task<Void, Never>?

        var isRunning: Bool { run != nil }

        private enum Limits {
            // series at a time. politeness is the host gate's job - this is pace,
            // and six across four hosts keeps every host inside its own budget
            static let width = 6
        }

        // nonisolated so Compositor can build it: that init opens the database
        // and runs migrations, so it cannot be on the main actor. legal because
        // this only assigns empty values
        nonisolated init(
            database: DatabaseClient,
            registry: Registry,
            refresher: Refresh,
            log: AppLog = .shared
        ) {
            self.database = database
            self.registry = registry
            self.refresher = refresher
            self.log = log
        }

        func start(collection: CollectionRecord.ID? = nil, named name: String? = nil) {
            guard run == nil else { return }

            let sort = LibrarySort(
                rawValue: UserDefaults.standard.string(forKey: Preferences.Key.librarySort) ?? ""
            ) ?? Preferences.Default.librarySort
            let ascending = UserDefaults.standard.object(forKey: Preferences.Key.librarySortAscending) as? Bool
                ?? Preferences.Default.librarySortAscending

            scope = name
            current = nil
            completed = 0
            total = 0
            failures = 0

            run = Task { [weak self] in
                await self?.walk(collection: collection, sort: sort, ascending: ascending)
                self?.finish()
            }
        }

        func cancel() {
            run?.cancel()
            Task { [refresher] in await refresher.cancelAll() }
        }

        private func finish() {
            run = nil
            active = []
            current = nil
            scope = nil
            total = 0
        }

        private func walk(collection: CollectionRecord.ID?, sort: LibrarySort, ascending: Bool) async {
            let work: [Series]
            do {
                work = try await database.reader.read { [registry] db in
                    try Self.work(collection: collection, sort: sort, ascending: ascending, registry: registry, in: db)
                }
            } catch {
                log.log("library refresh could not build its work list — \(error)", category: "refresh")
                return
            }

            guard !work.isEmpty else { return }
            total = work.count
            log.log("library refresh walking \(work.count) series", category: "refresh")

            // a fixed width rather than one task per series: two hundred tasks
            // all parked at the host gate is the same wall clock and a far worse
            // thing to cancel
            await withTaskGroup(of: Result.self) { group in
                var pending = work.makeIterator()

                for _ in 0..<min(Limits.width, work.count) {
                    guard let series = pending.next() else { break }
                    active.insert(series.id)
                    current = series.title
                    group.addTask { [refresher] in await Self.check(series, with: refresher) }
                }

                while let result = await group.next() {
                    active.remove(result.id)
                    completed += 1
                    failures += result.failures

                    guard !Task.isCancelled else { continue }

                    if let series = pending.next() {
                        active.insert(series.id)
                        current = series.title
                        group.addTask { [refresher] in await Self.check(series, with: refresher) }
                    }
                }
            }
        }

        // every origin of a series at once, exactly as the Details screen does -
        // it is the same unit, so a series refreshed from either place behaves
        // the same way. nonisolated: the walk must not run on the main actor,
        // only the numbers it reports live there
        nonisolated private static func check(_ series: Series, with refresher: Refresh) async -> Result {
            await withTaskGroup(of: Bool.self) { group in
                for origin in series.origins {
                    group.addTask {
                        let outcome = await refresher.chapters(
                            source: origin.source,
                            seriesSlug: origin.slug,
                            originId: origin.id
                        )
                        if case .failed = outcome { return true }
                        return false
                    }
                }

                var failures = 0
                for await failed in group where failed { failures += 1 }
                return Result(id: series.id, failures: failures)
            }
        }

        private struct Result: Sendable {
            let id: Int64
            let failures: Int
        }
    }
}

// MARK: - Work list

extension Compositor.LibraryRefresh {
    fileprivate struct Series: Sendable {
        let id: Int64
        let title: String
        let origins: [Origin]
    }

    fileprivate struct Origin: Sendable {
        let id: OriginRecord.ID
        let slug: String
        let source: Source
    }

    private struct Row: Decodable, FetchableRecord {
        let seriesId: Int64
        let title: String
        let originId: Int64
        let originSlug: String
        let sourceSlug: String
    }

    // one query, ordered the way the library the user is looking at is ordered,
    // then grouped in swift - the order has to survive the grouping, so this
    // walks the rows rather than using Dictionary(grouping:)
    fileprivate static func work(
        collection: CollectionRecord.ID?,
        sort: LibrarySort,
        ascending: Bool,
        registry: Compositor.Registry,
        in db: Database
    ) throws -> [Series] {
        let ordering = "e.\(column(for: sort)) \(ascending ? "ASC" : "DESC")"
        let scope = collection == nil ? "" : """
            AND EXISTS(
                SELECT 1 FROM \(SeriesCollectionRecord.databaseTableName) sc
                WHERE sc.\(SeriesCollectionRecord.Columns.seriesId.name) = e.\(EntryView.Columns.seriesId.name)
                  AND sc.\(SeriesCollectionRecord.Columns.collectionId.name) = ?
            )
            """

        let sql = """
            SELECT
                e.\(EntryView.Columns.seriesId.name) AS seriesId,
                e.\(EntryView.Columns.title.name) AS title,
                o.id AS originId,
                o.\(OriginRecord.Columns.slug.name) AS originSlug,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(EntryView.databaseTableName) e
            JOIN \(OriginRecord.databaseTableName) o
              ON o.\(OriginRecord.Columns.seriesId.name) = e.\(EntryView.Columns.seriesId.name)
            JOIN \(SourceRecord.databaseTableName) src
              ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE e.\(EntryView.Columns.inLibrary.name) = 1
              AND src.\(SourceRecord.Columns.installed.name) = 1
              AND src.\(SourceRecord.Columns.disabled.name) = 0
              \(scope)
            ORDER BY \(ordering), e.\(EntryView.Columns.seriesId.name) ASC,
                     o.\(OriginRecord.Columns.priority.name) ASC, o.id ASC
            """

        let rows = try Row.fetchAll(
            db,
            sql: sql,
            arguments: collection.map { StatementArguments([$0.rawValue]) } ?? StatementArguments()
        )

        var series: [Series] = []
        var currentId: Int64?
        var currentTitle = ""
        var origins: [Origin] = []

        func flush() {
            guard let id = currentId, !origins.isEmpty else { return }
            series.append(Series(id: id, title: currentTitle, origins: origins))
        }

        for row in rows {
            if row.seriesId != currentId {
                flush()
                currentId = row.seriesId
                currentTitle = row.title
                origins = []
            }

            // a source row can outlive the code that reads it, and an origin
            // nothing can open is not work
            guard let source = registry.source(slug: row.sourceSlug) else { continue }
            origins.append(
                Origin(id: OriginRecord.ID(rawValue: row.originId), slug: row.originSlug, source: source)
            )
        }
        flush()

        return series
    }

    // the enum is exhaustive here on purpose: a new sort option should not
    // compile until the walk knows how to order by it
    private static func column(for sort: LibrarySort) -> String {
        switch sort {
        case .added: EntryView.Columns.addedDate.name
        case .updated: EntryView.Columns.updatedDate.name
        case .lastRead: EntryView.Columns.lastReadDate.name
        case .unread: EntryView.Columns.unreadCount.name
        case .title: EntryView.Columns.title.name
        }
    }
}

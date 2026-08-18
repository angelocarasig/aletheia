//
//  Compositor+Metadata.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import BackgroundTasks
import Foundation
import GRDB
import Observation
import Tagged
import UIKit

extension Compositor {
    // reuses Refresh's origin metadata fetch and Trackers' own rather than a
    // second worker, so a Details-triggered refresh and this walk touching the
    // same origin concurrently join through the machinery OriginRefresher
    // already has. see docs/features/metadata-refresh.md
    @MainActor
    @Observable
    final class Metadata {
        private let database: DatabaseClient
        private let registry: Registry
        private let refresher: Refresh
        private let trackers: Trackers
        private let log: AppLog

        private(set) var total = 0
        private(set) var completed = 0
        private(set) var updated = 0
        private(set) var failures = 0

        @ObservationIgnored private var run: Task<Void, Never>?
        @ObservationIgnored private var automatic = false

        var isRunning: Bool { run != nil }

        private enum Limits {
            // matches Compositor.Refresh's width - the same host gates protect both
            static let width = 6
        }

        nonisolated init(
            database: DatabaseClient,
            registry: Registry,
            refresher: Refresh,
            trackers: Trackers,
            log: AppLog = .shared
        ) {
            self.database = database
            self.registry = registry
            self.refresher = refresher
            self.trackers = trackers
            self.log = log
        }

        func start(automatic: Bool = false) {
            guard run == nil else { return }
            self.automatic = automatic
            total = 0
            completed = 0
            updated = 0
            failures = 0

            run = Task { [weak self] in
                await self?.walk()
                if let self, !Task.isCancelled { await self.report() }
                self?.finish()
            }
        }

        func cancel() {
            guard isRunning else { return }
            log.log("metadata run cancelled at \(completed) of \(total)", category: "metadata")
            run?.cancel()
        }

        private func finish() {
            stamp()
            run = nil
            total = 0
        }

        private func report() async {
            guard UIApplication.shared.applicationState != .active else { return }
            await Notifier.metadataRefreshed(
                updated: updated, series: completed, failures: failures)
        }

        private func walk() async {
            let work: [Series]
            do {
                work = try await database.reader.read { [registry] db in
                    try Self.work(registry: registry, in: db)
                }
            } catch {
                log.log(
                    "metadata refresh could not build its work list - \(error)",
                    level: .error,
                    category: "metadata"
                )
                return
            }

            guard !work.isEmpty else { return }
            total = work.count
            log.log("metadata refresh walking \(work.count) series", category: "metadata")

            await withTaskGroup(of: Void.self) { group in
                var pending = work
                func take() -> Series? { pending.isEmpty ? nil : pending.removeFirst() }

                for _ in 0..<min(Limits.width, work.count) {
                    guard let series = take() else { break }
                    group.addTask { [weak self] in await self?.check(series) }
                }

                while await group.next() != nil {
                    completed += 1
                    guard !Task.isCancelled else { continue }
                    if let series = take() {
                        group.addTask { [weak self] in await self?.check(series) }
                    }
                }
            }
        }

        // sequential within the series, no per-series task group - metadata's
        // per-request cost is small enough not to need one
        private func check(_ series: Series) async {
            for origin in series.origins {
                guard let source = registry.source(slug: origin.sourceSlug) else { continue }
                let outcome = await refresher.metadata(
                    source: source,
                    seriesSlug: origin.slug,
                    originId: origin.id
                )
                record(outcome)
            }

            for link in series.trackers {
                let outcome = await trackers.refreshMetadata(link)
                record(outcome)
            }
        }

        private func record(_ outcome: MetadataOutcome) {
            switch outcome {
            case .updated: updated += 1
            case .failed: failures += 1
            case .unchanged, .cancelled: break
            }
        }

        // MARK: The schedule

        // one stamp, not two like Compositor.Refresh - there is no manual
        // whole-library trigger here that the automatic schedule needs protecting from
        private func stamp() {
            UserDefaults.standard.set(Date.now, forKey: Preferences.Key.metadataRefreshedDate)
            schedule()
        }

        func schedule(asap: Bool = false) {
            let interval =
                MetadataRefreshInterval(
                    rawValue: UserDefaults.standard.string(
                        forKey: Preferences.Key.metadataRefreshInterval) ?? ""
                ) ?? Preferences.Default.metadataRefreshInterval

            #if targetEnvironment(simulator)
                log.log(
                    "scheduled metadata refresh skipped - the simulator never accepts one",
                    category: "metadata")
            #else
                BGTaskScheduler.shared.cancel(
                    taskRequestWithIdentifier: Constants.Tasks.scheduledMetadataRefresh)

                guard let seconds = interval.seconds else {
                    log.log(
                        "scheduled metadata refresh cancelled - automatic checks are off",
                        category: "metadata")
                    return
                }

                let request = BGProcessingTaskRequest(
                    identifier: Constants.Tasks.scheduledMetadataRefresh)
                request.requiresNetworkConnectivity = true
                request.requiresExternalPower = false
                request.earliestBeginDate = asap ? nil : anchor.addingTimeInterval(seconds)

                do {
                    try BGTaskScheduler.shared.submit(request)
                    log.log(
                        "scheduled metadata refresh armed - \(request.earliestBeginDate.map { "no earlier than \($0.formatted())" } ?? "at the system's next opportunity")",
                        category: "metadata"
                    )
                } catch {
                    log.log(
                        "scheduled metadata refresh not accepted - \(error)", category: "metadata")
                }
            #endif
        }

        // the system may simply never run the scheduled task, so the interval is
        // also checked on app open
        func catchUp() {
            let defaults = UserDefaults.standard
            let interval =
                MetadataRefreshInterval(
                    rawValue: defaults.string(forKey: Preferences.Key.metadataRefreshInterval) ?? ""
                ) ?? Preferences.Default.metadataRefreshInterval

            guard let seconds = interval.seconds, !isRunning else { return }

            guard let last = defaults.object(forKey: Preferences.Key.metadataRefreshedDate) as? Date
            else {
                defaults.set(Date.now, forKey: Preferences.Key.metadataRefreshedDate)
                schedule()
                return
            }

            guard Date.now >= last.addingTimeInterval(seconds) else { return }

            log.log("automatic metadata refresh was due - running now", category: "metadata")
            start(automatic: true)
        }

        private var anchor: Date {
            UserDefaults.standard.object(forKey: Preferences.Key.metadataRefreshedDate) as? Date
                ?? .now
        }

        // MARK: The background task

        func adopt(_ task: BGTask) {
            task.expirationHandler = { Task { @MainActor [weak self] in self?.cancel() } }
            start(automatic: true)

            Task { @MainActor [weak self] in
                guard let self else { return task.setTaskCompleted(success: false) }
                while self.isRunning {
                    try? await Task.sleep(for: .seconds(1))
                }
                task.setTaskCompleted(success: true)
            }
        }
    }
}

// MARK: - The work list

extension Compositor.Metadata {
    fileprivate struct Series: Sendable {
        let id: Int64
        let origins: [Origin]
        let trackers: [SeriesTrackerRecord]
    }

    fileprivate struct Origin: Sendable {
        let id: OriginRecord.ID
        let slug: String
        let sourceSlug: String
    }

    private struct Row: Decodable, FetchableRecord {
        let seriesId: Int64
        let originId: Int64
        let originSlug: String
        let sourceSlug: String
    }

    // oldest-first rotation: a BGProcessingTask can be cut off at any point, so
    // a truncated run has to be cumulative rather than always covering the same
    // head of the library. a series with no metadata row sorts first under
    // SQLite's NULL-first ASC ordering, which is correct - nothing has answered for it
    nonisolated fileprivate static func work(
        registry: Compositor.Registry,
        in db: Database
    ) throws -> [Series] {
        let skips = Skips.stored.clauses

        let originSQL = """
            SELECT
                e.\(EntryView.Columns.seriesId.name) AS seriesId,
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
              \(skips)
            ORDER BY (
                SELECT MIN(m.\(MetadataRecord.Columns.fetchedDate.name))
                FROM \(MetadataRecord.databaseTableName) m
                WHERE m.\(MetadataRecord.Columns.seriesId.name) = e.\(EntryView.Columns.seriesId.name)
            ) ASC, e.\(EntryView.Columns.seriesId.name) ASC
            """

        let rows = try Row.fetchAll(db, sql: originSQL)

        var origins: [Int64: [Origin]] = [:]
        var order: [Int64] = []

        for row in rows {
            // a source row can outlive its registered implementation
            guard registry.source(slug: row.sourceSlug) != nil else { continue }
            if origins[row.seriesId] == nil { order.append(row.seriesId) }
            origins[row.seriesId, default: []].append(
                Origin(
                    id: OriginRecord.ID(rawValue: row.originId), slug: row.originSlug,
                    sourceSlug: row.sourceSlug)
            )
        }

        // joined in Swift, not SQL - the table is small, and a series reachable
        // only through a tracker link (every source disabled or gone) still
        // needs to be in the walk. queried through entry_view, not the bare
        // series table, so the same skip clause governs both halves
        let libraryIds = Set(
            try Int64.fetchAll(
                db,
                sql: """
                    SELECT e.\(EntryView.Columns.seriesId.name)
                    FROM \(EntryView.databaseTableName) e
                    WHERE e.\(EntryView.Columns.inLibrary.name) = 1
                      \(skips)
                    """
            )
        )

        var trackers: [Int64: [SeriesTrackerRecord]] = [:]
        for link in try SeriesTrackerRecord.fetchAll(db) {
            let seriesId = link.seriesId.rawValue
            guard libraryIds.contains(seriesId) else { continue }
            if origins[seriesId] == nil && trackers[seriesId] == nil { order.append(seriesId) }
            trackers[seriesId, default: []].append(link)
        }

        return order.map { id in
            Series(id: id, origins: origins[id] ?? [], trackers: trackers[id] ?? [])
        }
    }

    // its own keys, separate from Compositor.Refresh.Skips - a series skipped
    // for chapters is not necessarily one the reader wants skipped for metadata
    fileprivate struct Skips: Sendable {
        var completed = false
        var unread = false
        var notStarted = false

        static var stored: Skips {
            let defaults = UserDefaults.standard
            return Skips(
                completed: defaults.bool(forKey: Preferences.Key.metadataSkipCompleted),
                unread: defaults.bool(forKey: Preferences.Key.metadataSkipUnread),
                notStarted: defaults.bool(forKey: Preferences.Key.metadataSkipNotStarted)
            )
        }

        var clauses: String {
            var parts: [String] = []

            if completed {
                parts.append(
                    "AND e.\(EntryView.Columns.status.name) != '\(Status.completed.rawValue)'")
                parts.append(
                    "AND e.\(EntryView.Columns.publication.name) != '\(Publication.Completed.rawValue)'"
                )
            }

            if unread {
                parts.append("AND e.\(EntryView.Columns.unreadCount.name) = 0")
            }

            if notStarted {
                parts.append(
                    "AND e.\(EntryView.Columns.lastReadDate.name) > '1970-01-01 00:00:00.000'")
            }

            return parts.joined(separator: "\n              ")
        }
    }
}

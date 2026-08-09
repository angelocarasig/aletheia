//
//  FailuresViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation

// what is failing right now, straight off origin.fetchError. observed rather
// than fetched once: the column is cleared the moment a source answers, so a
// successful retry has to take its own row off this screen without being told.
// see docs/features/background-activity.md 5.1
@MainActor
@Observable
final class FailuresViewModel {
    private let database: DatabaseClient
    private let registry: Compositor.Registry
    private let refresher: Compositor.Refresh

    private(set) var entries: [Entry]?
    private(set) var failure: Failure?
    private(set) var retrying: Set<Int64> = []

    @ObservationIgnored private var stream: Task<Void, Never>?

    init(database: DatabaseClient, registry: Compositor.Registry, refresher: Compositor.Refresh) {
        self.database = database
        self.registry = registry
        self.refresher = refresher
    }

    func observe() {
        guard stream == nil else { return }

        stream = Task { [weak self, database] in
            let observation = ValueObservation
                .tracking { db in try Self.stored(in: db) }
                .removeDuplicates()

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.entries = stored
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Failures")
                AppLog.shared.log("failures observation failed — \(error)", category: "activity")
            }
        }
    }

    // one origin, through the same unit everything else uses - so a retry here
    // joins a library run already checking this origin rather than racing it
    func retry(_ entry: Entry) async {
        guard let source = registry.source(slug: entry.sourceSlug) else { return }
        guard !retrying.contains(entry.id) else { return }

        retrying.insert(entry.id)
        defer { retrying.remove(entry.id) }

        _ = await refresher.chapters(
            source: source,
            seriesSlug: entry.slug,
            originId: OriginRecord.ID(rawValue: entry.id)
        )
    }

    nonisolated private static func stored(in db: Database) throws -> [Entry] {
        let sql = """
            SELECT
                o.id AS id,
                o.\(OriginRecord.Columns.seriesId.name) AS seriesId,
                o.\(OriginRecord.Columns.slug.name) AS slug,
                o.\(OriginRecord.Columns.fetchError.name) AS reason,
                o.\(OriginRecord.Columns.fetchAttemptedDate.name) AS attemptedDate,
                e.\(EntryView.Columns.title.name) AS title,
                src.\(SourceRecord.Columns.name.name) AS sourceName,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(OriginRecord.databaseTableName) o
            JOIN \(EntryView.databaseTableName) e
              ON e.\(EntryView.Columns.seriesId.name) = o.\(OriginRecord.Columns.seriesId.name)
            JOIN \(SourceRecord.databaseTableName) src
              ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE o.\(OriginRecord.Columns.fetchError.name) IS NOT NULL
              AND e.\(EntryView.Columns.inLibrary.name) = 1
            ORDER BY o.\(OriginRecord.Columns.fetchAttemptedDate.name) DESC, o.id ASC
            """

        return try Entry.fetchAll(db, sql: sql)
    }
}

extension FailuresViewModel {
    struct Entry: Decodable, FetchableRecord, Identifiable, Equatable, Sendable {
        let id: Int64
        let seriesId: Int64
        let slug: String
        let reason: String
        let attemptedDate: Date
        let title: String
        let sourceName: String
        let sourceSlug: String
    }
}

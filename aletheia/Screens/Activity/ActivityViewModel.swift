//
//  ActivityViewModel.swift
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
final class ActivityViewModel {
    private let database: DatabaseClient

    private(set) var snapshot: Snapshot?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    init(database: DatabaseClient) {
        self.database = database
    }

    func observe() {
        guard stream == nil else { return }
        stream = Task { [weak self, database] in
            let observation =
                ValueObservation
                .tracking { db in
                    try Self.stored(in: db)
                }
                .removeDuplicates()

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.snapshot = stored
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Activity")
                AppLog.shared.log(
                    "activity observation failed - \(error)", level: .error, category: "activity")
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

    nonisolated private static func stored(in db: Database) throws -> Snapshot {
        let lastChecked = try Date.fetchOne(
            db,
            sql: """
                SELECT MAX(o.\(OriginRecord.Columns.chaptersFetchedDate.name))
                FROM \(OriginRecord.databaseTableName) o
                JOIN \(SeriesRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.seriesId.name)
                WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1
                """
        ).flatMap { $0 > Date(timeIntervalSince1970: 0) ? $0 : nil }

        let downloadedChapters =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM \(ChapterRecord.databaseTableName)
                    WHERE \(ChapterRecord.Columns.path.name) IS NOT NULL
                    """
            ) ?? 0

        // fetchError clears the moment a source answers again, so this is currently-failing, not ever-failed
        let failingSources =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM \(OriginRecord.databaseTableName) o
                    JOIN \(SeriesRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.seriesId.name)
                    WHERE o.\(OriginRecord.Columns.fetchError.name) IS NOT NULL
                      AND s.\(SeriesRecord.Columns.inLibrary.name) = 1
                    """
            ) ?? 0

        return Snapshot(
            lastChecked: lastChecked,
            downloadedChapters: downloadedChapters,
            failingSources: failingSources
        )
    }

}

// MARK: - Snapshot

extension ActivityViewModel {
    struct Snapshot: Equatable, Sendable {
        let lastChecked: Date?
        let downloadedChapters: Int
        let failingSources: Int
    }

}

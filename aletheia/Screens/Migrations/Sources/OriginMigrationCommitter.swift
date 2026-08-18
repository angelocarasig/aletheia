//
//  OriginMigrationCommitter.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import GRDB
import Tagged

struct OriginMigrationCommitter: MigrationCommitting {
    let database: DatabaseClient
    let registry: Compositor.Registry
    let refresher: Compositor.Refresh
    let mode: OriginMigrationMode
    let log: AppLog

    init(
        database: DatabaseClient,
        registry: Compositor.Registry,
        refresher: Compositor.Refresh,
        mode: OriginMigrationMode,
        log: AppLog = .shared
    ) {
        self.database = database
        self.registry = registry
        self.refresher = refresher
        self.mode = mode
        self.log = log
    }

    func commit(_ entry: SourceMigrationEntry, candidate: MigrationCandidate) async
        -> MigrationOutcome
    {
        guard let source = registry.source(slug: candidate.sourceSlug) else {
            return .failed("That source is no longer installed.")
        }

        let newOriginId: OriginRecord.ID

        do {
            let detail = try await source.details(seriesSlug: candidate.stub.slug)

            newOriginId = try await database.writer.write { db in
                guard
                    let sourceId =
                        try SourceRecord
                        .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                        .filter(SourceRecord.Columns.slug == candidate.sourceSlug)
                        .fetchOne(db)
                else { throw RecordError.missingIdentifier }

                // existence guard: this source may already be attached (a
                // prior migration run, or added by hand from Details)
                let known =
                    try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter([detail.slug, candidate.stub.slug].contains(OriginRecord.Columns.slug))
                    .fetchOne(db)

                if let known, let id = known.id { return id }

                let (_, originId) = try DetailsComposer.write(
                    detail,
                    sourceId: sourceId,
                    matching: candidate.cover,
                    into: entry.existingSeriesId,
                    in: db
                )
                return originId
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            log.log(
                "migration commit could not attach '\(candidate.title)' - \(error)", level: .error,
                category: "migration")
            return .failed(Failure(error, fallback: "Couldn't attach the new source").sentence)
        }

        // the origin is committed already - a failure from here on is
        // reported, not rolled back
        do {
            let outcome = await refresher.chapters(
                source: source, seriesSlug: candidate.stub.slug, originId: newOriginId)

            switch outcome {
            case .failed(let reason): return .failed(reason)
            case .cancelled: return .cancelled
            case .added, .unchanged: break
            }

            try await database.writer.write { db in
                try Self.copyProgress(from: entry.id, to: newOriginId, in: db)
                try Self.reorder(
                    newOriginId, oldOriginId: entry.id, for: entry.seriesId, mode: mode, in: db)
            }

            return .saved
        } catch is CancellationError {
            return .cancelled
        } catch {
            log.log(
                "migration commit could not finish '\(candidate.title)' - \(error)", level: .error,
                category: "migration")
            return .failed(
                Failure(error, fallback: "Source attached, but chapters or progress failed")
                    .sentence)
        }
    }

    private static func copyProgress(
        from oldOriginId: OriginRecord.ID,
        to newOriginId: OriginRecord.ID,
        in db: Database
    ) throws {
        let old =
            try ChapterRecord
            .filter(ChapterRecord.Columns.originId == oldOriginId.rawValue)
            .fetchAll(db)
        guard !old.isEmpty else { return }

        let new =
            try ChapterRecord
            .filter(ChapterRecord.Columns.originId == newOriginId.rawValue)
            .fetchAll(db)
        let newByNumber = Dictionary(
            new.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })

        for chapter in old where chapter.progress > 0 {
            guard var target = newByNumber[chapter.number] else { continue }
            _ = try target.updateChanges(db) {
                $0.progress = chapter.progress
                $0.lastReadDate = chapter.lastReadDate
            }
        }
    }

    private static func reorder(
        _ newOriginId: OriginRecord.ID,
        oldOriginId: OriginRecord.ID,
        for seriesId: SeriesRecord.ID,
        mode: OriginMigrationMode,
        in db: Database
    ) throws {
        var ordered = try DetailsComposer.Sources.ordered(for: seriesId, in: db)
        ordered.removeAll { $0 == newOriginId }
        ordered.insert(newOriginId, at: 0)
        try DetailsComposer.Sources.assign(ordered, in: db)

        if mode == .migrate {
            _ = try OriginRecord.filter(key: oldOriginId.rawValue).deleteAll(db)
            try DetailsComposer.Sources.renumber(for: seriesId, in: db)
        }
    }
}

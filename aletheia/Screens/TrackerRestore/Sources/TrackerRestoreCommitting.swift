//
//  TrackerRestoreCommitting.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation
import GRDB
import Tagged

// the real Save chain: create, join the library, fetch chapters, mark
// progress, link the tracker. one seam, not five - a row either finishes all
// of it or it failed at a step, and nothing before that step is rolled back
// separately. once the series exists and is in the library it stays that
// way even if a later step fails - it is a real, if incomplete, library
// entry the reader can retry chapters/tracking on later from Details itself
protocol TrackerRestoreCommitting: Sendable {
    func commit(
        _ entry: TrackerImportEntry,
        candidate: TrackerRestoreCandidate,
        tracker: Tracker
    ) async -> TrackerRestoreOutcome
}

struct LiveTrackerRestoreCommitter: TrackerRestoreCommitting {
    let database: DatabaseClient
    let registry: Compositor.Registry
    let refresher: Compositor.Refresh
    let trackers: Compositor.Trackers
    let log: AppLog

    init(
        database: DatabaseClient,
        registry: Compositor.Registry,
        refresher: Compositor.Refresh,
        trackers: Compositor.Trackers,
        log: AppLog = .shared
    ) {
        self.database = database
        self.registry = registry
        self.refresher = refresher
        self.trackers = trackers
        self.log = log
    }

    func commit(
        _ entry: TrackerImportEntry,
        candidate: TrackerRestoreCandidate,
        tracker: Tracker
    ) async -> TrackerRestoreOutcome {
        guard let source = registry.source(slug: candidate.sourceSlug) else {
            return .failed("That source is no longer installed.")
        }

        let seriesId: SeriesRecord.ID
        let originId: OriginRecord.ID

        do {
            let detail = try await source.details(seriesSlug: candidate.stub.slug)

            (seriesId, originId) = try await database.writer.write { db in
                guard let sourceId = try SourceRecord
                    .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                    .filter(SourceRecord.Columns.slug == candidate.sourceSlug)
                    .fetchOne(db)
                else { throw RecordError.missingIdentifier }

                // a restore row can resolve to a series already known locally
                // - duplicated on the tracker's own list, or simply added by
                // hand before restoring - and a second create for the same
                // (sourceId, slug) trips origin's unique constraint. the same
                // existence check DetailsComposer's own "add a source" flow
                // uses (store(into:)) catches it here too, attaching to what
                // is already there instead of failing the whole row
                let known = try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter([detail.slug, candidate.stub.slug].contains(OriginRecord.Columns.slug))
                    .fetchOne(db)

                let ids: (SeriesRecord.ID, OriginRecord.ID)
                if let known, let originId = known.id {
                    ids = (known.seriesId, originId)
                } else {
                    ids = try DetailsComposer.write(
                        detail,
                        sourceId: sourceId,
                        matching: candidate.cover,
                        into: nil,
                        in: db
                    )
                }

                try DetailsComposer.Library.set(inLibrary: true, for: ids.0, in: db)
                return ids
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            log.log("restore commit could not create '\(candidate.title)' - \(error)", level: .error, category: "restore")
            return .failed(Failure(error, fallback: "Couldn't create this series").sentence)
        }

        // the series is real and in the library from here on - a failure past
        // this point is reported, not rolled back
        do {
            let outcome = await refresher.chapters(source: source, seriesSlug: candidate.stub.slug, originId: originId)

            switch outcome {
            case .failed(let reason): return .failed(reason)
            case .cancelled: return .cancelled
            case .added, .unchanged: break
            }

            try await database.writer.write { db in
                let numbers = try ChapterRecord
                    .filter(ChapterRecord.Columns.originId == originId.rawValue)
                    .select(ChapterRecord.Columns.number, as: Double.self)
                    .fetchAll(db)
                    .filter { $0 <= Double(entry.progress) }

                try ChapterRecord.apply(progress: 1.0, toNumbers: numbers, in: seriesId, monotonic: true, db: db)
            }

            let trackerCandidate = TrackerCandidate(
                id: entry.id,
                title: entry.title,
                totalChapters: entry.totalChapters
            )

            try await trackers.link(
                series: seriesId,
                tracker: tracker,
                candidate: trackerCandidate,
                status: Status(raw: entry.remoteStatus, for: tracker) ?? .planning
            )

            return .saved
        } catch is CancellationError {
            return .cancelled
        } catch {
            log.log("restore commit could not finish '\(candidate.title)' - \(error)", level: .error, category: "restore")
            return .failed(Failure(error, fallback: "Series was created, but chapters or tracking failed").sentence)
        }
    }
}

// MARK: - Mapping

// a restore session pulls from exactly one tracker, so every entry.remoteStatus
// in it is that tracker's own raw vocabulary - this is the one place that
// vocabulary is not already known statically, so the dispatch lives here
// rather than on Status itself
private extension Status {
    init?(raw: String, for tracker: Tracker) {
        switch tracker {
        case .anilist: self.init(anilist: raw)
        case .myAnimeList: self.init(mal: raw)
        case .mangaBaka: self.init(mangaBaka: raw)
        }
    }
}

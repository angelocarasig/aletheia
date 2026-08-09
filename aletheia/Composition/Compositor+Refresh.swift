//
//  Compositor+Refresh.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import GRDB
import Tagged

extension Compositor {
    // one origin, checked once. this is the unit both a Details pull-to-refresh
    // and a whole-library walk call - v2 kept two copies of it and they had
    // drifted within a year, so there is exactly one here.
    //
    // an actor rather than a value because it holds one thing: which origins are
    // being fetched right now. a screen refreshing a series the library walk is
    // already touching is ordinary, and one place that knows beats every caller
    // deciding for itself. see docs/features/background-activity.md 6.4
    actor Refresh {
        private let database: DatabaseClient
        private let log: AppLog
        private var inFlight: [OriginRecord.ID: Task<Outcome, Never>] = [:]

        init(database: DatabaseClient, log: AppLog = .shared) {
            self.database = database
            self.log = log
        }

        enum Outcome: Equatable, Sendable {
            case added(Int)
            case unchanged
            case failed(String)

            var count: Int {
                if case let .added(count) = self { count } else { 0 }
            }
        }

        // a second caller for an origin already in flight joins it rather than
        // skipping: you pulled to refresh and are owed the real answer, not
        // "someone else has it". one request, both callers get its result
        func chapters(
            source: Source,
            seriesSlug: String,
            originId: OriginRecord.ID
        ) async -> Outcome {
            if let existing = inFlight[originId] {
                return await existing.value
            }

            // registered before the first suspension. an actor releases between
            // awaits, so a check-then-await-then-insert would let two callers
            // both find nothing and both fetch
            let task = Task { [weak self] in
                guard let self else { return Outcome.failed("Refresh was cancelled.") }
                let outcome = await self.perform(source: source, seriesSlug: seriesSlug, originId: originId)
                await self.finish(originId)
                return outcome
            }
            inFlight[originId] = task

            return await task.value
        }

        // metadata is a separate half so a library walk can skip it. a failure
        // here never blocks chapters - they are what a refresh is reaching for,
        // and the screen keeps what it has rather than nagging
        func metadata(source: Source, seriesSlug: String, originId: OriginRecord.ID) async {
            do {
                let detail = try await source.details(seriesSlug: seriesSlug)
                try await database.writer.write { db in
                    try Self.write(detail, for: originId, in: db)
                }
            } catch {
                log.log("origin \(originId.rawValue) metadata refresh failed — \(error)", category: "refresh")
            }
        }

        // the run cancels its work explicitly, because the fetch is unstructured:
        // a caller walking away must not kill a fetch another is still awaiting
        func cancel(originId: OriginRecord.ID) {
            inFlight[originId]?.cancel()
        }

        func cancelAll() {
            for task in inFlight.values { task.cancel() }
        }

        private func finish(_ originId: OriginRecord.ID) {
            inFlight[originId] = nil
        }

        private func perform(
            source: Source,
            seriesSlug: String,
            originId: OriginRecord.ID
        ) async -> Outcome {
            do {
                let stored = try await database.reader.read { db in
                    try ChapterRecord
                        .filter(ChapterRecord.Columns.originId == originId.rawValue)
                        .fetchCount(db)
                }

                // a source that can say cheaply whether anything moved is asked
                // that instead. everyone else is asked for the list, which is the
                // whole of the base contract
                let listing: ChapterRevalidation
                if let revalidating = source as? any RevalidatingSource {
                    listing = try await revalidating.chapters(seriesSlug: seriesSlug, stored: stored)
                } else {
                    listing = .changed(try await source.chapters(seriesSlug: seriesSlug))
                }
                let fetched = Date.now

                let added = try await database.writer.write { db -> Int in
                    var inserted = 0
                    if case let .changed(entries) = listing, !entries.isEmpty {
                        inserted = try Self.upsert(entries, for: originId, in: db)
                    }

                    // the source answered either way, so the date is stamped
                    // either way - only a throw leaves the stored list unknown
                    _ = try OriginRecord
                        .filter(key: originId.rawValue)
                        .updateAll(
                            db,
                            OriginRecord.Columns.chaptersFetchedDate.set(to: fetched),
                            OriginRecord.Columns.fetchAttemptedDate.set(to: fetched),
                            OriginRecord.Columns.fetchError.set(to: nil)
                        )

                    // insert-or-ignore, so this only ever heals a series created
                    // before seeding existed - a saved order is never touched
                    if let origin = try OriginRecord.fetchOne(db, key: originId.rawValue) {
                        try SeriesLanguagePriorityRecord.seedDefaults(for: origin.seriesId, in: db)
                    }

                    return inserted
                }

                log.log(
                    "origin \(originId.rawValue) \(listing.summary), \(added) new, had \(stored)",
                    category: "refresh"
                )

                return added > 0 ? .added(added) : .unchanged
            } catch {
                let failure = Failure(error, fallback: "Couldn't Load Chapters")
                let reason = failure.message.isEmpty ? failure.title : failure.message

                // the row outlives the run: the source keeps saying it is failing
                // until an attempt succeeds, which is why this is a column rather
                // than a variable
                try? await database.writer.write { db in
                    _ = try OriginRecord
                        .filter(key: originId.rawValue)
                        .updateAll(
                            db,
                            OriginRecord.Columns.fetchAttemptedDate.set(to: Date.now),
                            OriginRecord.Columns.fetchError.set(to: reason)
                        )
                }

                log.log("origin \(originId.rawValue) chapter fetch FAILED — \(error)", category: "refresh")
                return .failed(reason)
            }
        }
    }
}

// MARK: - Writes

extension Compositor.Refresh {
    // metadata a refresh is allowed to overwrite. titles and covers are add-only,
    // so a pick the user made can never be taken away by a later fetch
    nonisolated fileprivate static func write(
        _ detail: SeriesDetail,
        for originId: OriginRecord.ID,
        in db: Database
    ) throws {
        guard var origin = try OriginRecord.fetchOne(db, key: originId.rawValue) else { return }

        _ = try origin.updateChanges(db) {
            $0.synopsis = detail.synopsis
            $0.classification = detail.classification
            $0.publication = detail.publication
            $0.metadataFetchedDate = .now
        }

        for value in [detail.title] + detail.altTitles {
            _ = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: origin.seriesId, originId: originId, value: value),
                in: db
            )
        }

        for url in detail.covers {
            _ = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: origin.seriesId, originId: originId, url: url, path: nil),
                in: db
            )
        }
    }

    // chapters arrive independently of the rest of a series, so this runs on its
    // own and is safe to repeat. progress, lastReadDate and addedDate are never
    // overwritten - the update path lists the fields it touches, and none of
    // those are among them, so a row keeps its progress and the day it arrived
    @discardableResult
    nonisolated fileprivate static func upsert(
        _ entries: [ChapterEntry],
        for originId: OriginRecord.ID,
        in db: Database
    ) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        var inserted = 0

        var scanlators: [String: ScanlatorRecord.ID] = [:]
        for entry in entries where scanlators[entry.scanlator] == nil {
            let scanlator = try ScanlatorRecord.findOrCreate(
                ScanlatorRecord(id: nil, name: entry.scanlator),
                in: db
            )
            guard let scanlatorId = scanlator.id else { continue }
            scanlators[entry.scanlator] = scanlatorId

            // order of first appearance, and only when absent - a refresh must not
            // discard an ordering the user has since set
            var priority = OriginScanlatorPriorityRecord(
                originId: originId,
                scanlatorId: scanlatorId,
                priority: scanlators.count - 1
            )
            try priority.insert(db, onConflict: .ignore)
        }

        let existing = try ChapterRecord
            .filter(ChapterRecord.Columns.originId == originId)
            .fetchAll(db)
        let bySlug = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in entries {
            guard let scanlatorId = scanlators[entry.scanlator] else { continue }

            if var current = bySlug[entry.slug] {
                // diffed against the stored encoding, so a source that returned
                // nothing new issues no UPDATE and wakes no observation
                _ = try current.updateChanges(db) {
                    $0.title = entry.title
                    $0.number = entry.number
                    $0.publishedDate = entry.publishedDate
                    $0.language = entry.language
                    $0.url = entry.url
                }
            } else {
                var chapter = ChapterRecord(
                    id: nil,
                    originId: originId,
                    scanlatorId: scanlatorId,
                    slug: entry.slug,
                    title: entry.title,
                    number: entry.number,
                    publishedDate: entry.publishedDate,
                    language: entry.language,
                    progress: 0,
                    lastReadDate: nil,
                    url: entry.url,
                    path: nil
                )
                try chapter.insert(db)
                inserted += 1
            }
        }

        return inserted
    }
}

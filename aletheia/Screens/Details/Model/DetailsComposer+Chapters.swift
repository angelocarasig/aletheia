//
//  DetailsComposer+Chapters.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Tagged
import Observation
import struct SwiftUI.ImageResource

extension DetailsComposer {
    @MainActor
    @Observable
    final class Chapters: DetailsApplying, DetailsWriting {
        private(set) var chapters: [Row] = []
        private(set) var showAll = false
        private(set) var showHalf = true

        // from DetailsWriting
        private(set) var saving = false
        private(set) var failure: Failure?

        // which series this is for, taken as the bundle goes past. nothing
        // draws it, so it stays out of observation
        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        private let database: DatabaseClient

        init(database: DatabaseClient) {
            self.database = database
        }

        // from DetailsApplying
        func apply(_ stored: Stored) {
            seriesId = stored.series.id

            if chapters != stored.chapters { chapters = stored.chapters }
            if showAll != stored.series.showAllChapters { showAll = stored.series.showAllChapters }
            if showHalf != stored.series.showHalfChapters { showHalf = stored.series.showHalfChapters }
        }

        // from DetailsWriting
        func clear() {
            failure = nil
        }

        // where a tapped chapter goes, or nil if it cannot be opened. it does
        // not open anything - navigation has to happen in the tap itself, so
        // this stays synchronous and open() does the writing behind it
        func read(_ chapter: Row) -> Target? {
            guard let seriesId else { return nil }
            guard chapters.contains(where: { $0.id == chapter.id }) else { return nil }

            return Target(
                seriesId: seriesId,
                chapterId: ChapterRecord.ID(rawValue: chapter.id)
            )
        }

        // stamps the series as read and moves its status to .reading, which is what keeps
        // the launch purge from deleting it. the page position itself is
        // written by the reader, not here
        func open(_ chapter: Row) async {
            guard let seriesId else { return }
            let opened = Date.now

            do {
                try await database.writer.write { db in
                    // by number, so opening a chapter marks it opened whichever
                    // source ends up serving it
                    try ChapterRecord.apply(
                        readDate: opened,
                        toNumbers: [chapter.number],
                        in: seriesId,
                        db: db
                    )

                    try SeriesRecord.markRead(seriesId, at: opened, db: db)
                }
            } catch {
                failure = Failure(error, fallback: "Couldn't Open Chapter")
            }
        }

        // a confirmation to put in front of a bulk mark, or nil to just do it.
        // asked for one chapter at a time it is always nil
        func request(read: Bool, numbers: [Double]) -> Request? {
            let unique = Set(numbers)
            guard unique.count > 1 else { return nil }

            let touched = chapters.filter { unique.contains($0.number) }
            let losing = touched.filter {
                read ? ($0.progress > 0 && $0.progress < 1) : $0.progress > 0
            }

            return Request(
                read: read,
                numbers: Array(unique),
                scope: unique.count,
                affected: Set(losing.map(\.number)).count
            )
        }

        // writes progress for these chapter numbers across every origin that
        // carries them. leaves the read date alone, because marking is
        // bookkeeping rather than reading
        func mark(read: Bool, numbers: [Double]) async {
            guard let seriesId else { return }
            let numbers = Array(Set(numbers))
            guard !numbers.isEmpty else { return }

            saving = true
            defer { saving = false }

            do {
                try await database.writer.write { db in
                    // clearing is the one write allowed to move progress
                    // backwards - marking unread has to actually reach rows
                    // that were read
                    try ChapterRecord.apply(
                        progress: read ? 1.0 : 0.0,
                        toNumbers: numbers,
                        in: seriesId,
                        monotonic: read,
                        db: db
                    )

                    // one push for the batch maximum rather than one per
                    // number. unmarking lowers the furthest-read number, which enqueue
                    // simply declines to write - a tracker is never told to
                    // forget a chapter
                    try SeriesTrackerRecord.enqueue(for: seriesId, in: db)
                }
            } catch {
                failure = Failure(error, fallback: "Couldn't Update Progress")
            }
        }

        // off, the list is one row per chapter number. on, every source's copy
        // of a number is its own row. it overrides the half filter too, since a
        // list showing everything cannot be hiding halves
        func show(all value: Bool) async {
            await write(SeriesRecord.Columns.showAllChapters, value)
        }

        // whether half chapters, the .5 numbers, appear in the list
        func show(half value: Bool) async {
            await write(SeriesRecord.Columns.showHalfChapters, value)
        }

        private func write(_ column: Column, _ value: Bool) async {
            guard let seriesId else { return }

            saving = true
            defer { saving = false }

            do {
                try await database.writer.write { db in
                    _ = try SeriesRecord
                        .filter(key: seriesId.rawValue)
                        .updateAll(db, column.set(to: value))
                }
            } catch {
                failure = Failure(error, fallback: "Couldn't Update Visibility")
            }
        }
    }
}

extension DetailsComposer.Chapters {
    struct Row: Identifiable, Hashable {
        let id: Int64
        let number: Double
        let title: String
        let scanlator: String
        let language: LanguageCode
        let publishedDate: Date
        let progress: Double
        let url: URL

        // nil when the origin's source is no longer installed
        let sourceIcon: ImageResource?

        // an uninstalled or disabled source can still show its chapters, but
        // nothing can fetch pages for them
        let canRead: Bool

        // this row's own bytes, not this chapter number's. two sources serving
        // chapter 44 are two rows with two paths, and downloading one says
        // nothing about the other
        let downloaded: Bool

        var finished: Bool { progress >= 1 }
    }

    // where the reader opens. it says only which series and which chapter,
    // because the reader resolves its own chapter list and page urls from
    // those. it is a navigation value, so it has to compare on something
    // stable, and a pair of row ids is that
    struct Target: Hashable, Identifiable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID

        var id: Int64 { chapterId.rawValue }
    }

    // a bulk mark waiting to be confirmed. returned instead of written when the
    // change is big enough to be worth asking about, so the screen can put up a
    // dialog and call mark() only if the reader agrees. nil means go ahead
    struct Request: Identifiable {
        // fresh per prompt, so the screen can tell one confirmation from the
        // next even when the same chapters are picked twice
        let id = UUID()

        // true marks the chapters finished, false clears them back to unread
        let read: Bool

        // the chapter numbers to write. by number rather than by row, so the
        // write reaches every origin carrying that number
        let numbers: [Double]

        // how many chapters the reader picked. this is the number the dialog
        // leads with, because it is what they think they asked for
        let scope: Int

        // how many of those lose something they would miss, which is a page
        // position part way through a chapter. lower than scope, because
        // marking read only overwrites chapters left unfinished
        let affected: Int
    }
}

// the chapter list as it is read and shaped. both run on the database queue:
// turning four hundred rows into display rows costs about 700ms, and that is a
// frame, so neither the raw row nor the mapping ever reaches the main actor
extension DetailsComposer.Chapters {
    nonisolated static func rows(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [Chapter] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(ChapterRecord.Columns.slug.name) AS slug,
                c.\(ChapterRecord.Columns.title.name) AS title,
                c.\(ChapterRecord.Columns.number.name) AS number,
                c.\(ChapterRecord.Columns.language.name) AS language,
                c.\(ChapterRecord.Columns.progress.name) AS progress,
                c.\(ChapterRecord.Columns.url.name) AS url,
                c.\(ChapterRecord.Columns.path.name) AS path,
                c.\(ChapterRecord.Columns.publishedDate.name) AS publishedDate,
                s.\(ScanlatorRecord.Columns.name.name) AS scanlator,
                o.\(OriginRecord.Columns.slug.name) AS originSlug,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(BestChapterView.databaseTableName) bc ON bc.chapterId = c.id
            JOIN \(ScanlatorRecord.databaseTableName) s ON s.id = c.\(ChapterRecord.Columns.scanlatorId.name)
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE bc.seriesId = ?
              -- rank = 1 is the deduplicated list. showAllChapters drops that
              -- filter entirely, so every source's copy of a number is a row
              AND (bc.showAllChapters = 1 OR bc.rank = 1)
              -- isVisible already folds in showAllChapters and showHalfChapters
              AND bc.isVisible = 1
            ORDER BY bc.number ASC
            """

        return try Chapter.fetchAll(db, sql: sql, arguments: [id])
    }

    // not carried in the bundle, unlike the other row types - it is read here
    // and handed straight to display(), so it never reaches the main actor
    struct Chapter: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let slug: String
        let title: String
        let number: Double
        let language: LanguageCode
        let progress: Double
        let url: URL
        let path: String?
        let publishedDate: Date
        let scanlator: String
        let originSlug: String
        let sourceSlug: String?
    }

    // ordered the way best_chapter ranks them: priority first, id as the
    // deterministic tiebreak, unavailable sources last. the icon resolves
    // through the registry, so a source no longer compiled in yields nil and
    // the row renders a placeholder
    nonisolated static func display(
        _ rows: [Chapter],
        registry: Compositor.Registry
    ) -> [Row] {
        rows.map { row in
            let source = row.sourceSlug.flatMap { registry.source(slug: $0) }

            return Row(
                id: row.id,
                number: row.number,
                title: row.title,
                scanlator: row.scanlator,
                language: row.language,
                publishedDate: row.publishedDate,
                progress: row.progress,
                url: row.url,
                sourceIcon: source?.descriptor.icon,
                canRead: source != nil,
                downloaded: row.path != nil
            )
        }
    }
}

//
//  DetailsComposer+Chapters.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Observation
import Tagged

import struct SwiftUI.ImageResource

extension DetailsComposer {
    @MainActor
    @Observable
    final class Chapters: DetailsApplying, DetailsWriting {
        private(set) var chapters: [Row] = []
        private(set) var showAll = false
        private(set) var showHalf = true

        private(set) var saving = false
        private(set) var failure: Failure?

        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        private let database: DatabaseClient

        init(database: DatabaseClient) {
            self.database = database
        }

        func apply(_ stored: Stored) {
            seriesId = stored.series.id

            if chapters != stored.chapters { chapters = stored.chapters }
            if showAll != stored.series.showAllChapters { showAll = stored.series.showAllChapters }
            if showHalf != stored.series.showHalfChapters {
                showHalf = stored.series.showHalfChapters
            }
        }

        func clear() {
            failure = nil
        }

        // synchronous and does not write - navigation must happen in the tap
        // itself, so open() does the writing separately, behind it
        func read(_ chapter: Row) -> Target? {
            guard let seriesId else { return nil }
            guard chapters.contains(where: { $0.id == chapter.id }) else { return nil }

            return Target(
                seriesId: seriesId,
                chapterId: ChapterRecord.ID(rawValue: chapter.id)
            )
        }

        // moves the series to .reading, which is what keeps the launch purge
        // from deleting it - the page position itself is written by the reader
        func open(_ chapter: Row) async {
            guard let seriesId else { return }
            let opened = Date.now

            do {
                try await database.writer.write { db in
                    // by number, so this marks the chapter opened whichever
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

        // leaves the read date alone - marking is bookkeeping, not reading
        func mark(read: Bool, numbers: [Double]) async {
            guard let seriesId else { return }
            let numbers = Array(Set(numbers))
            guard !numbers.isEmpty else { return }

            saving = true
            defer { saving = false }

            do {
                try await database.writer.write { db in
                    // monotonic only when marking read - marking unread must be
                    // able to move progress backwards
                    try ChapterRecord.apply(
                        progress: read ? 1.0 : 0.0,
                        toNumbers: numbers,
                        in: seriesId,
                        monotonic: read,
                        db: db
                    )

                    // unmarking lowers the furthest-read number, which enqueue
                    // declines to write - a tracker is never told to forget a
                    // chapter
                    try SeriesTrackerRecord.enqueue(for: seriesId, in: db)
                }
            } catch {
                failure = Failure(error, fallback: "Couldn't Update Progress")
            }
        }

        // also overrides the half filter - a list showing everything cannot be
        // hiding halves
        func show(all value: Bool) async {
            await write(SeriesRecord.Columns.showAllChapters, value)
        }

        func show(half value: Bool) async {
            await write(SeriesRecord.Columns.showHalfChapters, value)
        }

        private func write(_ column: Column, _ value: Bool) async {
            guard let seriesId else { return }

            saving = true
            defer { saving = false }

            do {
                try await database.writer.write { db in
                    _ =
                        try SeriesRecord
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

        let sourceIcon: ImageResource?
        let canRead: Bool

        // per row, not per chapter number - two sources serving chapter 44 are
        // two rows with two paths, and downloading one says nothing about the other
        let downloaded: Bool

        var finished: Bool { progress >= 1 }
    }

    struct Target: Hashable, Identifiable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID

        var id: Int64 { chapterId.rawValue }
    }

    struct Request: Identifiable {
        // fresh per prompt, so the same chapters picked twice still get their
        // own confirmation
        let id = UUID()

        let read: Bool
        let numbers: [Double]
        let scope: Int

        // marking read only counts chapters left partway through as affected;
        // marking unread counts every chapter that had progress at all
        let affected: Int
    }
}

// both run on the database queue: turning four hundred rows into display rows
// costs about 700ms, which is a frame, so neither step reaches the main actor
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
              -- rank = 1 is the deduplicated list; showAllChapters drops the
              -- filter so every source's copy of a number is its own row
              AND (bc.showAllChapters = 1 OR bc.rank = 1)
              -- isVisible already folds in showAllChapters and showHalfChapters
              AND bc.isVisible = 1
            ORDER BY bc.number ASC
            """

        return try Chapter.fetchAll(db, sql: sql, arguments: [id])
    }

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

    // order is whatever rows(for:in:) returned (number ascending); this just
    // maps. the icon resolves through the registry, so a source no longer
    // compiled in yields nil and the row renders a placeholder
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

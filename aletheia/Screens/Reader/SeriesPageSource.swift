//
//  SeriesPageSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import CoreGraphics
import Foundation
import GRDB
import Tagged

// the seam between the reader and everything it must not know about. the engine
// asks for pages by chapter id; resolving that into a download on disk or a
// request to a source happens entirely here
struct SeriesPageSource: ReaderPageSource {
    let database: DatabaseClient
    let registry: Compositor.Registry
    let fill: ChapterFill

    func pages(for chapter: ReaderChapter.ID) async throws -> [ReaderPage] {
        // the token the engine holds and the row that answers for it are two
        // different things the moment a source is swapped. every ReaderPage below
        // still carries the token, so nothing downstream has to know
        let id = await fill.row(for: chapter)

        guard let row = try await database.reader.read({ db in
            try Self.locate(id, in: db)
        }) else {
            throw ReaderError.notFound(chapter)
        }

        // a downloaded chapter reads off disk whatever happened to its source,
        // so the local path is checked before the origin is judged unavailable
        if let stored = Constants.Paths.resolve(row.path) {
            let files = try Self.files(in: stored)
            guard !files.isEmpty else { throw ReaderError.noPages(chapter) }

            return files.enumerated().map { index, url in
                ReaderPage(chapter: chapter, index: index, url: url)
            }
        }

        guard let slug = row.sourceSlug, let source = registry.source(slug: slug) else {
            throw ReaderError.unavailable(chapter)
        }

        let content = try await source.content(
            seriesSlug: row.originSlug,
            chapterSlug: row.slug
        )
        guard !content.isEmpty else { throw ReaderError.noPages(chapter) }

        let headers = source.requestHeaders

        // the page number you see on screen is 1-based, so it is logged that way
        // - the whole point is being able to read "page 7 looks wrong" off the
        // screen and find the url that served it
        for page in content {
            AppLog.shared.log(
                "page \(page.index + 1)/\(content.count) — \(page.url.absoluteString)",
                category: "reader.pages"
            )
        }

        return content.map { page in
            ReaderPage(
                chapter: chapter,
                index: page.index,
                url: page.url,
                headers: headers,
                // ratio-grade hints are fine here - the reader only ever uses
                // this to pick a height, never to decide a split
                size: page.size.map { CGSize(width: $0.width, height: $0.height) }
            )
        }
    }

    // MARK: Private

    private struct Located: Decodable, FetchableRecord, Sendable {
        let slug: String
        let path: String?
        let originSlug: String
        let sourceSlug: String?
    }

    private static func locate(_ id: ChapterRecord.ID, in db: Database) throws -> Located? {
        let sql = """
            SELECT
                c.\(ChapterRecord.Columns.slug.name) AS slug,
                c.\(ChapterRecord.Columns.path.name) AS path,
                o.\(OriginRecord.Columns.slug.name) AS originSlug,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src
                ON src.id = o.\(OriginRecord.Columns.sourceId.name)
                AND src.\(SourceRecord.Columns.disabled.name) = 0
            WHERE c.id = ?
            """

        return try Located.fetchOne(db, sql: sql, arguments: [id.rawValue])
    }

    // a stored chapter is a directory of zero-padded parts, so lexicographic
    // order is page order and no archive has to be unpacked to read it
    private static func files(in directory: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: directory.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        guard exists else { return [] }
        guard isDirectory.boolValue else { return [directory] }

        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

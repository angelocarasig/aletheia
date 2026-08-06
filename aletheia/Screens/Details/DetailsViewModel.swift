//
//  DetailsViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import SwiftUI
import GRDB
import Tagged
import Observation

// what the screen needs before a view model can exist. a sourced entry carries
// both already; a library entry has to resolve them from its primary origin
struct DetailsRoute {
    let source: Source
    let stub: SeriesStub
}

extension DetailsViewModel {
    static func route(
        for entry: SeriesEntry,
        registry: Compositor.Registry,
        database: DatabaseClient = .client
    ) async -> DetailsRoute? {
        switch entry {
        case .source(let slug, let stub):
            guard let source = registry.source(slug: slug) else { return nil }
            return DetailsRoute(source: source, stub: stub)

        case .library(let id):
            // entry_view already picks the primary origin - available sources
            // first, then by priority - so its slug is the one that source knows
            let resolved = try? await database.reader.read { db -> (EntryView, String)? in
                guard let row = try EntryView
                    .filter(EntryView.Columns.seriesId == id.rawValue)
                    .fetchOne(db),
                    let sourceId = row.sourceId,
                    let source = try SourceRecord.fetchOne(db, key: sourceId)
                else { return nil }

                return (row, source.slug)
            }

            guard let (row, slug) = resolved ?? nil,
                  let source = registry.source(slug: slug)
            else { return nil }

            return DetailsRoute(
                source: source,
                stub: SeriesStub(
                    slug: row.slug,
                    title: row.title,
                    cover: row.cover,
                    latestChapterNumber: nil,
                    latestChapterDate: nil
                )
            )
        }
    }
}

@MainActor
@Observable
final class DetailsViewModel {
    private let source: Source
    private let stub: SeriesStub
    private let database: DatabaseClient
    private let registry: Compositor.Registry

    private(set) var detail: SeriesDetail?
    private(set) var chapters: [ChapterEntry] = []
    private(set) var match: SeriesMatch?
    private(set) var inLibrary = false
    private(set) var status: Status = .planning
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var stored: [DetailsChapters.Chapter] = []
    private(set) var covers: [DetailsCovers.Cover] = []
    private(set) var origins: [DetailsSources.Origin] = []
    private(set) var candidates: [DetailsDisambiguation.Candidate] = []
    private(set) var resolved = false
    private(set) var isFetchingChapters = false
    private(set) var chaptersFetchedDate: Date = .distantPast
    private(set) var metadataFetchedDate: Date = .distantPast

    var lastMetadataFetch: Date? { metadataFetchedDate > .distantPast ? metadataFetchedDate : nil }

    // an empty chapter list only means "none" once a fetch has actually landed
    var hasFetchedChapters: Bool { chaptersFetchedDate > .distantPast }

    // observed, not ignored: isReady and canToggleLibrary are computed from
    // these, so a view reading them has to be invalidated when they land
    private var seriesId: SeriesRecord.ID?
    private var originId: OriginRecord.ID?

    var title: String { detail?.title ?? stub.title }
    var canToggleLibrary: Bool { seriesId != nil && !isSaving }

    // shown until the user either attaches to one of them or keeps this separate
    var needsDisambiguation: Bool { !candidates.isEmpty && !resolved }

    // nothing real renders until the series is settled - matching can land on a
    // different series than the stub that opened it, and the title would change
    var isReady: Bool { detail != nil && seriesId != nil && !needsDisambiguation }

    var authors: [String] { detail?.authors ?? [] }
    // sources return tags in their own order, so sort for display. localized
    // standard compare is case insensitive and orders any numbers naturally
    var tags: [String] {
        (detail?.tags ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    // the stored preference wins once it is known, so picking a new primary cover
    // updates the header and backdrop straight away
    var cover: URL? {
        covers.first { $0.isPreferred }?.url ?? detail?.covers.first ?? stub.cover
    }


    var collections: [DetailsCollections.Item] { [] }

    // the stored list is deduplicated across origins and carries read progress.
    // the fetched list stands in only until the first write lands
    var chapterDisplays: [DetailsChapters.Chapter] {
        stored.isEmpty ? fetched : stored
    }

    private var fetched: [DetailsChapters.Chapter] {
        chapters.map {
            DetailsChapters.Chapter(
                id: $0.slug,
                number: $0.number,
                title: $0.title,
                scanlator: $0.scanlator,
                language: $0.language,
                publishedDate: $0.publishedDate,
                progress: 0,
                sourceIcon: source.descriptor.icon
            )
        }
    }

    init(
        source: Source,
        stub: SeriesStub,
        registry: Compositor.Registry,
        database: DatabaseClient = .client
    ) {
        self.source = source
        self.stub = stub
        self.registry = registry
        self.database = database
    }

    // chapters fetch alongside the series and land later. nothing about the
    // series - including add to library - waits on them
    func load() async {
        guard detail == nil else { return }

        isLoading = true
        async let chapterList: Void = fetchChapters()

        await fetchDetail()
        await store()
        await refresh()
        // anything already stored renders before the chapter fetch returns, so a
        // known series is readable straight away
        await loadStoredChapters()
        await loadOrigins()
        await loadCovers()
        isLoading = false

        await chapterList
        await storeChapters()
    }

    // nil clears the pick, handing the choice back to origin priority
    func setPreferredCover(_ id: Int64?) async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, SeriesRecord.Columns.preferredCoverId.set(to: id))
            }
            await loadCovers()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setStatus(_ value: Status) async {
        guard let seriesId, value != status else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                _ = try SeriesRecord
                    .filter(key: seriesId.rawValue)
                    .updateAll(db, SeriesRecord.Columns.status.set(to: value.rawValue))
            }
            status = value
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleLibrary() async {
        guard let seriesId else { return }

        isSaving = true
        defer { isSaving = false }

        let value = !inLibrary
        do {
            try await database.writer.write { db in
                try Self.setInLibrary(value, for: seriesId, in: db)
            }
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Network

    private func fetchDetail() async {
        do { detail = try await source.details(seriesSlug: stub.slug) }
        catch { errorMessage = String(describing: error) }
    }

    private func fetchChapters() async {
        isFetchingChapters = true
        defer { isFetchingChapters = false }

        // this runs alongside store(), so originId is not set yet - resolve the
        // count straight from the source's own slug instead of waiting for it
        let have = await knownChapterCount()

        do {
            // nil means the source checked and nothing changed, so the stored
            // list stands and there is nothing to write
            if let fetched = try await source.chapters(seriesSlug: stub.slug, have: have) {
                chapters = fetched
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func knownChapterCount() async -> Int {
        let sourceSlug = source.descriptor.slug
        let seriesSlug = stub.slug

        let count = try? await database.reader.read { db -> Int in
            guard let sourceId = try SourceRecord
                .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                .filter(SourceRecord.Columns.slug == sourceSlug)
                .fetchOne(db),
                let origin = try OriginRecord
                    .select(OriginRecord.Columns.id, as: OriginRecord.ID.self)
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter(OriginRecord.Columns.slug == seriesSlug)
                    .fetchOne(db)
            else { return 0 }

            return try ChapterRecord
                .filter(ChapterRecord.Columns.originId == origin)
                .fetchCount(db)
        }
        return count ?? 0
    }

    // MARK: - Persistence

    private func refresh() async {
        let stub = stub
        let sourceSlug = source.descriptor.slug
        let id = seriesId

        let state = try? await database.reader.read { db -> (SeriesMatch, SeriesRecord?) in
            let match = try SeriesRecord.match(stub, from: sourceSlug, in: db)
            let saved = try id.flatMap { try SeriesRecord.fetchOne(db, key: $0.rawValue) }
            return (match, saved)
        }

        match = state?.0
        inLibrary = state?.1?.inLibrary ?? false
        status = state?.1?.status ?? .planning

        // a series opened again already knows whether its chapters ever landed,
        // so it never falls back to claiming it has none
        if let originId {
            let origin = try? await database.reader.read { db in
                try OriginRecord.fetchOne(db, key: originId.rawValue)
            }
            chaptersFetchedDate = origin?.chaptersFetchedDate ?? .distantPast
            metadataFetchedDate = origin?.metadataFetchedDate ?? .distantPast
        }

        await loadCandidates()
    }

    private func loadCandidates() async {
        guard case .candidates(let ids) = match?.outcome else {
            candidates = []
            return
        }

        do {
            let rows = try await database.reader.read { db in
                try Self.candidates(for: ids, in: db)
            }

            candidates = rows.map { row in
                let referer = row.sourceSlug
                    .flatMap { registry.source(slug: $0) }?
                    .descriptor.referer

                return DetailsDisambiguation.Candidate(
                    id: row.id,
                    title: row.title,
                    cover: row.cover,
                    referer: referer,
                    authors: row.authors,
                    sourceCount: row.sourceCount,
                    chapterCount: row.chapterCount
                )
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // reparents this source's origin onto the chosen series and drops the row
    // that was created for it, so the two never both sit in the library
    func attach(to target: Int64) async {
        guard let seriesId, let originId, seriesId.rawValue != target else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await database.writer.write { db in
                try Self.reparent(originId: originId, from: seriesId, to: SeriesRecord.ID(rawValue: target), in: db)
            }

            self.seriesId = SeriesRecord.ID(rawValue: target)
            resolved = true

            await refresh()
            await loadStoredChapters()
            await loadOrigins()
            await loadCovers()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func keepSeparate() {
        resolved = true
    }

    // eager: the series lands in the database as soon as its details arrive,
    // out of library
    private func store() async {
        guard let detail, seriesId == nil else { return }

        let cover = stub.cover
        let sourceSlug = source.descriptor.slug

        do {
            let stored = try await database.writer.write { db -> (SeriesRecord.ID, OriginRecord.ID) in
                guard let sourceId = try SourceRecord
                    .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                    .filter(SourceRecord.Columns.slug == sourceSlug)
                    .fetchOne(db)
                else { throw DetailsError.missingIdentifier }

                // the details response carries the canonical slug, which can differ
                // from the one the stub was opened with
                let known = try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter(OriginRecord.Columns.slug == detail.slug)
                    .fetchOne(db)

                let seriesId = try known?.seriesId ?? Self.create(
                    from: detail,
                    sourceId: sourceId,
                    matching: cover,
                    in: db
                )

                guard let originId = try OriginRecord
                    .select(OriginRecord.Columns.id, as: OriginRecord.ID.self)
                    .filter(OriginRecord.Columns.sourceId == sourceId)
                    .filter(OriginRecord.Columns.slug == detail.slug)
                    .fetchOne(db)
                else { throw DetailsError.missingIdentifier }

                return (seriesId, originId)
            }

            seriesId = stored.0
            originId = stored.1
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func storeChapters() async {
        guard !chapters.isEmpty else { return }
        guard let originId else {
            AppLog.shared.log("skipped storing \(chapters.count) chapter(s) — no origin yet", category: "details")
            return
        }
        let entries = chapters

        do {
            let fetched = Date.now
            try await database.writer.write { db in
                try Self.upsert(entries, for: originId, in: db)
                // stamped only on a write that landed, so a failed fetch leaves
                // the origin looking unfetched rather than empty
                _ = try OriginRecord
                    .filter(key: originId.rawValue)
                    .updateAll(db, OriginRecord.Columns.chaptersFetchedDate.set(to: fetched))
            }
            chaptersFetchedDate = fetched
            await loadStoredChapters()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func loadOrigins() async {
        guard let seriesId else { return }

        do {
            let rows = try await database.reader.read { db in
                try Self.origins(for: seriesId, in: db)
            }

            origins = rows.map { row in
                // three different unavailabilities, and they need different
                // answers from the user: re-enable it, re-attach it, or accept
                // the source no longer ships with the app
                let source = row.sourceSlug.flatMap { registry.source(slug: $0) }
                let availability: DetailsSources.Origin.Availability =
                    if row.disconnected { .disconnected }
                    else if source == nil { .missing }
                    else if row.disabled { .disabled }
                    else { .available }

                return DetailsSources.Origin(
                    id: row.id,
                    name: source?.descriptor.name ?? row.sourceSlug ?? "Unknown Source",
                    host: source?.descriptor.baseURL.host() ?? row.sourceSlug ?? "",
                    icon: source?.descriptor.icon,
                    priority: row.priority,
                    chapterCount: row.chapterCount,
                    fetchedDate: row.chaptersFetchedDate > .distantPast ? row.chaptersFetchedDate : nil,
                    availability: availability
                )
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func loadCovers() async {
        guard let seriesId else { return }

        do {
            let rows = try await database.reader.read { db in
                try Self.covers(for: seriesId, in: db)
            }

            covers = rows.map { row in
                let source = row.sourceSlug.flatMap { registry.source(slug: $0) }
                return DetailsCovers.Cover(
                    id: row.id,
                    url: row.url,
                    sourceName: source?.descriptor.name,
                    sourceIcon: source?.descriptor.icon,
                    isPreferred: row.isPreferred
                )
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func loadStoredChapters() async {
        guard let seriesId else { return }

        do {
            let rows = try await database.reader.read { db in
                try Self.chapters(for: seriesId, in: db)
            }

            // the icon resolves through the registry, so a source that is no longer
            // compiled in yields nil and the row renders a placeholder
            stored = rows.map { row in
                DetailsChapters.Chapter(
                    id: row.slug,
                    number: row.number,
                    title: row.title,
                    scanlator: row.scanlator,
                    language: row.language,
                    publishedDate: row.publishedDate,
                    progress: row.progress,
                    sourceIcon: row.sourceSlug.flatMap { registry.source(slug: $0)?.descriptor.icon }
                )
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Writes

    nonisolated private static func create(
        from detail: SeriesDetail,
        sourceId: SourceRecord.ID,
        matching stubCover: URL?,
        in db: Database
    ) throws -> SeriesRecord.ID {
        var series = SeriesRecord()
        try series.insert(db)
        guard let seriesId = series.id else { throw DetailsError.missingIdentifier }

        var origin = OriginRecord(
            id: nil,
            seriesId: seriesId,
            sourceId: sourceId,
            slug: detail.slug,
            url: detail.url.absoluteString,
            synopsis: detail.synopsis,
            priority: 0,
            classification: detail.classification,
            publication: detail.publication,
            // this origin exists because a details response just arrived
            metadataFetchedDate: .now
        )
        try origin.insert(db)
        guard let originId = origin.id else { throw DetailsError.missingIdentifier }

        // the source's own title goes in first, and becomes the preferred one
        var preferredTitleId: TitleRecord.ID?
        for value in [detail.title] + detail.altTitles {
            let title = try TitleRecord.findOrCreate(
                TitleRecord(id: nil, seriesId: seriesId, originId: originId, value: value),
                in: db
            )
            if preferredTitleId == nil { preferredTitleId = title.id }
        }

        let primary = primaryCover(among: detail.covers, matching: stubCover)
        var preferredCoverId: CoverRecord.ID?
        for url in detail.covers {
            let cover = try CoverRecord.findOrCreate(
                CoverRecord(id: nil, seriesId: seriesId, originId: originId, url: url, path: nil),
                in: db
            )
            if url == primary { preferredCoverId = cover.id }
        }

        for name in detail.authors {
            let author = try AuthorRecord.findOrCreate(AuthorRecord(id: nil, name: name), in: db)
            guard let authorId = author.id else { continue }
            var link = SeriesAuthorRecord(id: nil, seriesId: seriesId, authorId: authorId)
            try link.insert(db, onConflict: .ignore)
        }

        for name in detail.tags {
            let tag = try TagRecord.findOrCreate(
                TagRecord(id: nil, normalizedName: sanitised(name), displayName: name, canonicalId: nil),
                in: db
            )
            guard let tagId = tag.id else { continue }
            var link = SeriesTagRecord(id: nil, seriesId: seriesId, tagId: tagId)
            try link.insert(db, onConflict: .ignore)
        }

        // the creating origin is the only one there is, so it supplies everything
        series.preferredTitleId = preferredTitleId
        series.preferredCoverId = preferredCoverId
        series.preferredSynopsisOriginId = originId
        series.preferredMetadataOriginId = originId
        try series.update(db)

        return seriesId
    }

    // chapters arrive independently of the rest of a series, so this runs on its
    // own and is safe to repeat. progress and lastReadDate are never overwritten
    nonisolated private static func upsert(
        _ entries: [ChapterEntry],
        for originId: OriginRecord.ID,
        in db: Database
    ) throws {
        guard !entries.isEmpty else { return }

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
            }
        }
    }

    // best_chapter already picks one row per chapter number across every available
    // origin, and its isVisible column folds in the half-chapter preference
    nonisolated private static func chapters(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredChapter] {
        let sql = """
            SELECT
                c.\(ChapterRecord.Columns.slug.name) AS slug,
                c.\(ChapterRecord.Columns.title.name) AS title,
                c.\(ChapterRecord.Columns.number.name) AS number,
                c.\(ChapterRecord.Columns.language.name) AS language,
                c.\(ChapterRecord.Columns.progress.name) AS progress,
                c.\(ChapterRecord.Columns.publishedDate.name) AS publishedDate,
                s.\(ScanlatorRecord.Columns.name.name) AS scanlator,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(BestChapterView.databaseTableName) bc ON bc.chapterId = c.id
            JOIN \(ScanlatorRecord.databaseTableName) s ON s.id = c.\(ChapterRecord.Columns.scanlatorId.name)
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE bc.seriesId = ?
              AND bc.rank = 1
              AND bc.isVisible = 1
            ORDER BY bc.number ASC
            """

        return try StoredChapter.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    // ordered the way best_chapter ranks them: priority first, id as the
    // deterministic tiebreak, unavailable sources last
    nonisolated private static func origins(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredOrigin] {
        let sql = """
            SELECT
                o.id AS id,
                o.\(OriginRecord.Columns.priority.name) AS priority,
                o.\(OriginRecord.Columns.chaptersFetchedDate.name) AS chaptersFetchedDate,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                (o.\(OriginRecord.Columns.sourceId.name) IS NULL) AS disconnected,
                COALESCE(src.\(SourceRecord.Columns.disabled.name), 0) AS disabled,
                (
                    SELECT COUNT(*)
                    FROM \(ChapterRecord.databaseTableName) c
                    WHERE c.\(ChapterRecord.Columns.originId.name) = o.id
                ) AS chapterCount
            FROM \(OriginRecord.databaseTableName) o
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            ORDER BY
                (o.\(OriginRecord.Columns.sourceId.name) IS NULL OR COALESCE(src.\(SourceRecord.Columns.disabled.name), 0)) ASC,
                o.\(OriginRecord.Columns.priority.name) ASC,
                o.id ASC
            """

        return try StoredOrigin.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    nonisolated private static func covers(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredCover] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(CoverRecord.Columns.url.name) AS url,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                (c.id = s.\(SeriesRecord.Columns.preferredCoverId.name)) AS isPreferred
            FROM \(CoverRecord.databaseTableName) c
            JOIN \(SeriesRecord.databaseTableName) s ON s.id = c.\(CoverRecord.Columns.seriesId.name)
            LEFT JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(CoverRecord.Columns.originId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE c.\(CoverRecord.Columns.seriesId.name) = ?
            ORDER BY c.id ASC
            """

        return try StoredCover.fetchAll(db, sql: sql, arguments: [seriesId])
    }

    nonisolated private static func candidates(
        for ids: [SeriesRecord.ID],
        in db: Database
    ) throws -> [StoredCandidate] {
        guard !ids.isEmpty else { return [] }

        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT
                v.\(RichfulEntryView.Columns.seriesId.name) AS id,
                v.\(RichfulEntryView.Columns.title.name) AS title,
                v.\(RichfulEntryView.Columns.cover.name) AS cover,
                v.\(RichfulEntryView.Columns.authors.name) AS authors,
                v.\(RichfulEntryView.Columns.totalChapterCount.name) AS chapterCount,
                (SELECT COUNT(*) FROM \(OriginRecord.databaseTableName) o
                  WHERE o.\(OriginRecord.Columns.seriesId.name) = v.\(RichfulEntryView.Columns.seriesId.name)) AS sourceCount,
                (SELECT src.\(SourceRecord.Columns.slug.name)
                   FROM \(OriginRecord.databaseTableName) o
                   JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
                  WHERE o.\(OriginRecord.Columns.seriesId.name) = v.\(RichfulEntryView.Columns.seriesId.name)
                  ORDER BY o.\(OriginRecord.Columns.priority.name) ASC LIMIT 1) AS sourceSlug
            FROM \(RichfulEntryView.databaseTableName) v
            WHERE v.\(RichfulEntryView.Columns.seriesId.name) IN (\(placeholders))
            """

        return try StoredCandidate.fetchAll(db, sql: sql, arguments: StatementArguments(ids.map(\.rawValue)))
    }

    // titles and covers carry the origin, so they move with it. UPDATE OR IGNORE
    // because the target may already hold an identical title or cover url
    nonisolated private static func reparent(
        originId: OriginRecord.ID,
        from series: SeriesRecord.ID,
        to target: SeriesRecord.ID,
        in db: Database
    ) throws {
        let next = try Int.fetchOne(
            db,
            sql: """
                SELECT COALESCE(MAX(\(OriginRecord.Columns.priority.name)), -1) + 1
                FROM \(OriginRecord.databaseTableName)
                WHERE \(OriginRecord.Columns.seriesId.name) = ?
                """,
            arguments: [target]
        ) ?? 0

        try db.execute(
            sql: """
                UPDATE \(OriginRecord.databaseTableName)
                SET \(OriginRecord.Columns.seriesId.name) = ?, \(OriginRecord.Columns.priority.name) = ?
                WHERE id = ?
                """,
            arguments: [target, next, originId]
        )

        for table in [TitleRecord.databaseTableName, CoverRecord.databaseTableName] {
            try db.execute(
                sql: "UPDATE OR IGNORE \(table) SET seriesId = ? WHERE originId = ?",
                arguments: [target, originId]
            )
        }

        try db.execute(
            sql: "DELETE FROM \(SeriesRecord.databaseTableName) WHERE id = ?",
            arguments: [series]
        )
    }

    // removing resets addedDate, so a series re-added later takes a fresh date
    nonisolated private static func setInLibrary(
        _ inLibrary: Bool,
        for id: SeriesRecord.ID,
        in db: Database
    ) throws {
        _ = try SeriesRecord
            .filter(key: id.rawValue)
            .updateAll(
                db,
                SeriesRecord.Columns.inLibrary.set(to: inLibrary),
                SeriesRecord.Columns.addedDate.set(to: inLibrary ? Date.now : Date.distantPast)
            )
    }

    // exact url, else the same filename ignoring extension, else the first listed
    nonisolated private static func primaryCover(among covers: [URL], matching stub: URL?) -> URL? {
        guard let stub else { return covers.first }
        if let exact = covers.first(where: { $0 == stub }) { return exact }

        let stem = stub.deletingPathExtension().lastPathComponent
        return covers.first { $0.deletingPathExtension().lastPathComponent == stem } ?? covers.first
    }

    nonisolated private static func sanitised(_ tag: String) -> String {
        tag.lowercased().replacingOccurrences(of: " ", with: "")
    }
}

private enum DetailsError: Error {
    case missingIdentifier
}

private struct StoredCandidate: Decodable, FetchableRecord {
    let id: Int64
    let title: String
    let cover: URL?
    let authors: String?
    let chapterCount: Int
    let sourceCount: Int
    let sourceSlug: String?
}

private struct StoredOrigin: Decodable, FetchableRecord {
    let id: Int64
    let priority: Int
    let chapterCount: Int
    let chaptersFetchedDate: Date
    let sourceSlug: String?
    let disconnected: Bool
    let disabled: Bool
}

private struct StoredCover: Decodable, FetchableRecord {
    let id: Int64
    let url: URL
    let sourceSlug: String?
    let isPreferred: Bool
}

private struct StoredChapter: Decodable, FetchableRecord {
    let slug: String
    let title: String
    let number: Double
    let language: LanguageCode
    let progress: Double
    let publishedDate: Date
    let scanlator: String
    let sourceSlug: String?
}

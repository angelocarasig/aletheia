//
//  ReaderViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI
import Observation
import GRDB
import Tagged

@MainActor
@Observable
final class ReaderViewModel {
    private let seriesId: SeriesRecord.ID
    private let startingChapter: ChapterRecord.ID
    private let database: DatabaseClient
    private let registry: Compositor.Registry

    private(set) var engine: ReaderEngine?
    private(set) var failure: String?
    private(set) var isReady = false

    var isOverlayVisible = true

    // highest page reached per chapter. going backwards must never lower what
    // is stored, and a page already saved is never written twice
    @ObservationIgnored private var reached: [ChapterRecord.ID: (page: Int, total: Int)] = [:]
    @ObservationIgnored private var saved: [ChapterRecord.ID: Int] = [:]
    @ObservationIgnored private var lastSave: Date?
    @ObservationIgnored private var stored: [ChapterRecord.ID: Double] = [:]
    @ObservationIgnored private var icons: [ReaderChapter.ID: ImageResource] = [:]

    func sourceIcon(for chapter: ReaderChapter.ID?) -> ImageResource? {
        chapter.flatMap { icons[$0] }
    }

    private enum Save {
        static let throttle: TimeInterval = 3
    }

    init(
        seriesId: SeriesRecord.ID,
        chapterId: ChapterRecord.ID,
        database: DatabaseClient,
        registry: Compositor.Registry
    ) {
        self.seriesId = seriesId
        self.startingChapter = chapterId
        self.database = database
        self.registry = registry
    }

    // MARK: Lifecycle

    func load() async {
        guard engine == nil else { return }

        do {
            let loaded = try await database.reader.read { [seriesId] db in
                try Self.chapters(for: seriesId, in: db)
            }
            guard !loaded.isEmpty else {
                failure = "This series has no readable chapters."
                return
            }

            let orientation = try await database.reader.read { [seriesId] db in
                try SeriesRecord.fetchOne(db, key: seriesId.rawValue)?.orientation ?? .unknown
            }

            loaded.forEach { chapter in
                stored[ChapterRecord.ID(rawValue: chapter.id)] = chapter.progress
                // a series can carry origins from several sources, so the icon
                // is per chapter rather than per series
                icons[chapter.id] = chapter.sourceSlug
                    .flatMap { registry.source(slug: $0) }?
                    .descriptor.icon
            }

            var configuration = ReaderConfiguration()
            configuration.mode = orientation.resolved
            configuration.dim = ReaderSettings.dim
            configuration.chromeTint = ReaderSettings.chromeTint
            configuration.horizontalPadding = ReaderSettings.horizontalPadding
            configuration.autoScrollSpeed = ReaderSettings.autoScrollSpeed

            let engine = ReaderEngine(
                chapters: loaded.map {
                    ReaderChapter(id: $0.id, number: $0.number, title: $0.title)
                },
                boundaries: Self.boundaries(across: loaded),
                source: SeriesPageSource(database: database, registry: registry),
                configuration: configuration
            )
            bind(engine)
            self.engine = engine
            isReady = true

            let progress = stored[startingChapter]
            await engine.open(startingChapter.rawValue, progress: progress)
        } catch {
            failure = String(describing: error)
        }
    }

    func close() async {
        await flush()
    }

    // MARK: Settings

    func setMode(_ mode: Orientation) {
        guard var configuration = engine?.configuration else { return }
        configuration.mode = mode
        engine?.update(configuration)

        Task { [database, seriesId] in
            do {
                try await database.writer.write { db in
                    try SeriesRecord
                        .filter(SeriesRecord.Columns.id == seriesId.rawValue)
                        .updateAll(db, SeriesRecord.Columns.orientation.set(to: mode.rawValue))
                }
            } catch {
                AppLog.shared.log("failed to persist orientation — \(error)", category: "reader")
            }
        }
    }

    func setDim(_ value: Double) {
        guard var configuration = engine?.configuration else { return }
        configuration.dim = value
        ReaderSettings.dim = value
        engine?.update(configuration)
    }

    func setChromeTint(_ value: Double) {
        guard var configuration = engine?.configuration else { return }
        configuration.chromeTint = value
        ReaderSettings.chromeTint = value
        engine?.update(configuration)
    }

    func setHorizontalPadding(_ value: CGFloat) {
        guard var configuration = engine?.configuration else { return }
        configuration.horizontalPadding = value
        ReaderSettings.horizontalPadding = value
        engine?.update(configuration)
    }

    func setAutoScrollSpeed(_ value: CGFloat) {
        guard var configuration = engine?.configuration else { return }
        configuration.autoScrollSpeed = value
        ReaderSettings.autoScrollSpeed = value
        engine?.update(configuration)
    }

    // MARK: Tap handling

    func handleTap(at point: CGPoint) {
        guard let engine, surfaceFrame.width > 0, surfaceFrame.height > 0 else { return }

        let local = CGPoint(
            x: point.x - surfaceFrame.minX,
            y: point.y - surfaceFrame.minY
        )

        switch ReaderTapZones.action(
            at: local,
            in: surfaceFrame.size,
            layout: ReaderSettings.tapZone,
            reversed: ReaderSettings.tapZonesReversed
        ) {
        case .previous:
            engine.advance(forward: false)
        case .next:
            engine.advance(forward: true)
        case .menu:
            isOverlayVisible.toggle()
        }
    }

    // MARK: Private

    // what a boundary means before anything is loaded: what changed between the
    // two chapters, and whether any are missing between them. static, so it is
    // computed once rather than on every approach
    nonisolated private static func boundaries(
        across chapters: [StoredChapter]
    ) -> [ReaderChapter.ID: ReaderBoundaryInfo] {
        var result: [ReaderChapter.ID: ReaderBoundaryInfo] = [:]

        for (previous, next) in zip(chapters, chapters.dropFirst()) {
            var continuity = ReaderSeparatorModel.Continuity()
            if previous.sourceName != next.sourceName { continuity.source = next.sourceName }
            if previous.scanlator != next.scanlator { continuity.scanlator = next.scanlator }
            if previous.language != next.language { continuity.language = next.language.rawValue }

            let gap = ReaderSeparatorModel.Gap.between(previous.number, next.number)
            guard !continuity.isEmpty || gap != nil else { continue }

            result[previous.id] = ReaderBoundaryInfo(
                continuity: continuity.isEmpty ? nil : continuity,
                gap: gap
            )
        }

        return result
    }

    private func bind(_ engine: ReaderEngine) {
        engine.onPageChanged = { [weak self] chapter, index, total in
            self?.track(chapter: chapter, page: index, total: total)
        }

        engine.onChapterChanged = { [weak self] chapter, explicit in
            guard let self else { return }
            Task { await self.flush() }

            // stubs for phases the port deliberately defers - a transition
            // banner, a chapter-gap warning, session events and tracker sync
            // all hang off this one callback
            AppLog.shared.log(
                "chapter changed to \(chapter.number.formatted()) (explicit: \(explicit))",
                category: "reader"
            )
            AppLog.shared.log("TODO session addChapter", category: "reader")
        }

        engine.onChapterFinished = { [weak self] chapter in
            Task { await self?.complete(chapter) }
        }

        engine.onSingleTap = { [weak self] point in
            self?.handleTap(at: point)
        }
    }

    // the engine reports taps in window space so a zone stays where the reader
    // sees it rather than moving with the content. the screen keeps this in step
    // with its own geometry, which is all that is needed to convert
    @ObservationIgnored var surfaceFrame: CGRect = .zero

    private func track(chapter: ReaderChapter, page: Int, total: Int) {
        let id = ChapterRecord.ID(rawValue: chapter.id)
        let best = max(reached[id]?.page ?? 0, page)
        reached[id] = (best, total)

        Task { await save(id, throttled: true) }
    }

    // reaching the boundary is what finishes a chapter, not landing on its last
    // page - a page can be the last one on screen without ever being read past
    private func complete(_ chapter: ReaderChapter) async {
        let id = ChapterRecord.ID(rawValue: chapter.id)
        guard let entry = reached[id], entry.total > 0 else { return }

        reached[id] = (entry.total - 1, entry.total)
        await save(id, throttled: false)
        AppLog.shared.log(
            "finished chapter \(chapter.number.formatted()) — TODO tracker sync",
            category: "reader"
        )
    }

    private func flush() async {
        for id in reached.keys {
            await save(id, throttled: false)
        }
    }

    private func save(_ id: ChapterRecord.ID, throttled: Bool) async {
        guard let entry = reached[id], entry.total > 0 else { return }
        guard saved[id] != entry.page else { return }

        if throttled, let lastSave, Date.now.timeIntervalSince(lastSave) < Save.throttle {
            return
        }

        let progress = Double(entry.page + 1) / Double(entry.total)
        guard progress > (stored[id] ?? 0) else { return }

        do {
            try await database.writer.write { [seriesId] db in
                try ChapterRecord
                    .filter(ChapterRecord.Columns.id == id.rawValue)
                    .updateAll(
                        db,
                        ChapterRecord.Columns.progress.set(to: progress),
                        ChapterRecord.Columns.lastReadDate.set(to: Date.now)
                    )

                // the launch purge spares anything with a read date, so this
                // has to be written whether or not the series is in the library
                try SeriesRecord
                    .filter(SeriesRecord.Columns.id == seriesId.rawValue)
                    .updateAll(db, SeriesRecord.Columns.lastReadDate.set(to: Date.now))
            }

            saved[id] = entry.page
            stored[id] = progress
            lastSave = .now
        } catch {
            AppLog.shared.log("failed to save progress — \(error)", category: "reader")
        }
    }

    private struct StoredChapter: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let number: Double
        let title: String
        let progress: Double
        let language: LanguageCode
        let scanlator: String
        let sourceSlug: String?
        let sourceName: String?
    }

    nonisolated private static func chapters(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [StoredChapter] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(ChapterRecord.Columns.number.name) AS number,
                c.\(ChapterRecord.Columns.title.name) AS title,
                c.\(ChapterRecord.Columns.progress.name) AS progress,
                c.\(ChapterRecord.Columns.language.name) AS language,
                sc.\(ScanlatorRecord.Columns.name.name) AS scanlator,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(BestChapterView.databaseTableName) bc ON bc.chapterId = c.id
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            JOIN \(ScanlatorRecord.databaseTableName) sc ON sc.id = c.\(ChapterRecord.Columns.scanlatorId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE bc.seriesId = ?
              AND bc.rank = 1
              AND bc.isVisible = 1
            ORDER BY bc.number ASC
            """

        return try StoredChapter.fetchAll(db, sql: sql, arguments: [seriesId.rawValue])
    }
}

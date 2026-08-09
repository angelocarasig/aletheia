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

    // which row serves each chapter, for this reading session only. reopening
    // falls back to best_chapter's ranking
    private let fill = ChapterFill()

    private(set) var engine: ReaderEngine?
    private(set) var failure: Failure?
    private(set) var isReady = false

    private(set) var slots: [ChapterSlot] = []
    private(set) var isLoadingSlots = false

    // an observable mirror of what the fill actor holds, so the switcher can mark
    // the active option without awaiting an actor mid-render
    private(set) var fills: [ReaderChapter.ID: ChapterRecord.ID] = [:]

    var isOverlayVisible = true
    var isShowingTapZones = false
    private(set) var isFlashingTapZones = false

    // highest page reached per chapter. going backwards must never lower what
    // is stored, and a page already saved is never written twice
    @ObservationIgnored private var reached: [ChapterRecord.ID: (page: Int, total: Int)] = [:]
    @ObservationIgnored private var saved: [ChapterRecord.ID: Int] = [:]
    @ObservationIgnored private var lastSave: Date?
    @ObservationIgnored private var stored: [ChapterRecord.ID: Double] = [:]
    // observed, not ignored: a swap repoints a chapter at another source and the
    // header button has to follow, so this read has to register as a dependency
    private var icons: [ReaderChapter.ID: ImageResource] = [:]
    // read state is written per chapter NUMBER, not per row, so every save needs
    // the number behind the row it was handed
    @ObservationIgnored private var numbers: [ChapterRecord.ID: Double] = [:]

    // history rows carry a title snapshot because their seriesId is a soft
    // reference - the row must stay readable after a purge or merge
    @ObservationIgnored private var seriesTitle = ""

    // one sitting, accumulated in memory and inserted complete at the flush
    // points - never opened as a row and closed later. `entered` is the page
    // each chapter was at when the sitting began, so pagesRead is the sitting's
    // own advance rather than lifetime progress
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var entered: [ChapterRecord.ID: Int] = [:]
    @ObservationIgnored private var sessionChaptersRead = 0

    func sourceIcon(for chapter: ReaderChapter.ID?) -> ImageResource? {
        chapter.flatMap { icons[$0] }
    }

    @ObservationIgnored private var flash: Task<Void, Never>?

    private enum Save {
        static let throttle: TimeInterval = 3
    }

    private enum Flash {
        static let duration: Duration = .seconds(3)
        static let settle: Animation = .easeOut(duration: 0.2)
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
                // not an error anything threw - the query succeeded and the
                // answer is empty, which is permanent until a source is added
                failure = Failure(
                    title: "Nothing to Read",
                    message: "No installed source has chapters for this series.",
                    isRetryable: false
                )
                return
            }

            let (orientation, tags, title) = try await database.reader.read { [seriesId] db in
                let orientation = try SeriesRecord
                    .fetchOne(db, key: seriesId.rawValue)?.orientation ?? .unknown
                let tags = try TagRecord
                    .joining(required: TagRecord.seriesTags
                        .filter(SeriesTagRecord.Columns.seriesId == seriesId.rawValue))
                    .select(TagRecord.Columns.normalizedName, as: String.self)
                    .fetchSet(db)
                let title = try String.fetchOne(
                    db,
                    sql: """
                        SELECT \(EntryView.Columns.title.name)
                        FROM \(EntryView.databaseTableName)
                        WHERE \(EntryView.Columns.seriesId.name) = ?
                        """,
                    arguments: [seriesId.rawValue]
                ) ?? ""
                return (orientation, tags, title)
            }
            seriesTitle = title

            loaded.forEach { chapter in
                stored[ChapterRecord.ID(rawValue: chapter.id)] = chapter.progress
                numbers[ChapterRecord.ID(rawValue: chapter.id)] = chapter.number
                // a series can carry origins from several sources, so the icon
                // is per chapter rather than per series
                icons[chapter.id] = chapter.sourceSlug
                    .flatMap { registry.source(slug: $0) }?
                    .descriptor.icon
            }

            var configuration = ReaderConfiguration()
            configuration.mode = orientation.resolved(tags: tags)
            configuration.dim = ReaderSettings.dim
            configuration.chromeTint = ReaderSettings.chromeTint
            configuration.horizontalPadding = ReaderSettings.horizontalPadding
            configuration.autoScrollSpeed = ReaderSettings.autoScrollSpeed
            configuration.autoAdvanceInterval = ReaderSettings.autoAdvanceInterval

            let engine = ReaderEngine(
                chapters: loaded.map {
                    ReaderChapter(id: $0.id, number: $0.number, title: $0.title)
                },
                boundaries: Self.boundaries(across: loaded),
                source: SeriesPageSource(database: database, registry: registry, fill: fill),
                configuration: configuration
            )
            bind(engine)
            self.engine = engine
            isReady = true
            sessionStart = .now

            let opening = try await resolve(startingChapter, among: loaded)
            let progress = stored[ChapterRecord.ID(rawValue: opening)]
            await engine.open(opening, progress: progress)
        } catch {
            failure = Failure(error, fallback: "Can't Open This Series")
            AppLog.shared.log("reader open failed — \(error)", category: "reader")
        }
    }

    func close() async {
        await flush()
        await endSession()
    }

    // MARK: Scene lifecycle

    // backgrounding ends the sitting - one complete row, foreground time only.
    // returning starts a fresh sitting from the pages already reached, so
    // nothing is counted twice. .inactive deliberately does neither: a
    // notification shade or a call banner is not the end of a sitting
    func background() async {
        await flush()
        await endSession()
    }

    func foreground() {
        guard engine != nil, sessionStart == nil else { return }
        sessionStart = .now
        entered = reached.mapValues(\.page)
        sessionChaptersRead = 0
    }

    // MARK: Source switching

    func slot(for number: Double?) -> ChapterSlot? {
        guard let number else { return nil }
        return slots.first { $0.number == number }
    }

    func activeRow(for chapter: ReaderChapter.ID) -> ChapterRecord.ID {
        fills[chapter] ?? ChapterRecord.ID(rawValue: chapter)
    }

    // the engine keeps asking for the same chapter it always asked for. all that
    // changes is which row answers, and then the chapter is re-fetched in place
    func swap(to option: ChapterSlot.Option, for chapter: ReaderChapter.ID) async {
        guard let engine, option.id != activeRow(for: chapter) else { return }

        await fill.set(option.id, for: chapter)
        fills[chapter] = option.id.rawValue == chapter ? nil : option.id
        // the header button names the source you are reading from, so it moves
        // with the fill. swapping back to the default restores the original
        icons[chapter] = option.sourceIcon
        await engine.reload(chapter)
    }

    // MARK: Chapter list

    // read on demand rather than at open: a long series is thousands of rows once
    // every origin is counted, and none of it is needed to show a page.
    //
    // reloaded on every present, and the previous slots stay on screen while it
    // runs - progress moves as you read, so a cache held for the session would
    // show the list you had when you first opened it
    func loadSlots() async {
        guard !isLoadingSlots else { return }
        isLoadingSlots = true
        defer { isLoadingSlots = false }

        // progress saves are throttled, so what has been read can be newer here
        // than in the table for a few seconds. draining first makes the read the
        // source of truth rather than a snapshot that trails the reader
        await flush()

        do {
            let rows = try await database.reader.read { [seriesId] db in
                try Self.slotRows(for: seriesId, in: db)
            }
            slots = ChapterSlot.group(rows) { [registry] slug in
                registry.source(slug: slug)?.descriptor.icon
            }
        } catch {
            AppLog.shared.log("failed to load chapter list — \(error)", category: "reader")
        }
    }

    // MARK: Settings

    func setMode(_ mode: Orientation) {
        guard var configuration = engine?.configuration else { return }
        configuration.mode = mode
        engine?.update(configuration)

        Task { [database, seriesId] in
            do {
                try await database.writer.write { db in
                    _ = try SeriesRecord
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

    func setAutoAdvanceInterval(_ value: TimeInterval) {
        guard var configuration = engine?.configuration else { return }
        configuration.autoAdvanceInterval = value
        ReaderSettings.autoAdvanceInterval = value
        engine?.update(configuration)
    }

    // MARK: Tap zones

    // stored, not read straight off UserDefaults on demand: observation only
    // tracks stored properties, and a computed one left the picker's tick mark
    // pinned to whatever was selected when the sheet opened
    private(set) var tapZone: ReaderTapZones.Layout = ReaderSettings.tapZone
    private var isTapZoneFlipped: Bool = ReaderSettings.tapZonesReversed

    // what the zones do once the reading direction has had its say, which is
    // what every caller wants - the raw toggle is only ever half the answer
    var tapZonesReversed: Bool {
        ReaderTapZones.reversed(
            for: engine?.configuration.mode ?? .leftToRight,
            manual: isTapZoneFlipped
        )
    }

    var isReadingRightToLeft: Bool {
        engine?.configuration.mode.isRightToLeft ?? false
    }

    func setTapZone(_ layout: ReaderTapZones.Layout) {
        guard layout != tapZone else { return }
        tapZone = layout
        ReaderSettings.tapZone = layout
        flashTapZones()
    }

    // the picker shows the resolved state, so what comes back is resolved too -
    // stored as the manual half by taking the direction back out of it
    func setTapZonesReversed(_ value: Bool) {
        let manual = value != isReadingRightToLeft
        guard manual != isTapZoneFlipped else { return }
        isTapZoneFlipped = manual
        ReaderSettings.tapZonesReversed = manual
        flashTapZones()
    }

    // three seconds, not the 700ms this used to run for: the flash exists to
    // teach a layout you have never seen, and it was gone before it registered
    func flashTapZones() {
        guard tapZone != .off else { return }

        flash?.cancel()
        flash = Task { [weak self] in
            withAnimation(Flash.settle) { self?.isFlashingTapZones = true }
            try? await Task.sleep(for: Flash.duration)
            guard !Task.isCancelled else { return }
            withAnimation(Flash.settle) { self?.isFlashingTapZones = false }
        }
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
            layout: tapZone,
            reversed: tapZonesReversed
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

    // the tap carries a chapter row, but what the reader was asked for is a point
    // on the series' number line. which row wins a number moves when a source is
    // disabled or origins are reordered, so a row tapped off a list drawn a moment
    // earlier may no longer be the one to open - resolve through the number rather
    // than trusting the id. falls back to the tapped row so the engine still
    // reports a real error when the number itself has gone
    private func resolve(
        _ tapped: ChapterRecord.ID,
        among chapters: [StoredChapter]
    ) async throws -> ReaderChapter.ID {
        if chapters.contains(where: { $0.id == tapped.rawValue }) { return tapped.rawValue }

        let number = try await database.reader.read { db in
            try Double.fetchOne(
                db,
                sql: """
                    SELECT \(ChapterRecord.Columns.number.name)
                    FROM \(ChapterRecord.databaseTableName)
                    WHERE id = ?
                    """,
                arguments: [tapped.rawValue]
            )
        }

        guard let number else { return tapped.rawValue }
        return chapters.first { $0.number == number }?.id ?? tapped.rawValue
    }

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

        engine.onChapterFinished = { [weak self] chapter, pages in
            Task { await self?.complete(chapter, pages: pages) }
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
        if entered[id] == nil { entered[id] = page }
        let best = max(reached[id]?.page ?? 0, page)
        reached[id] = (best, total)

        Task { await save(id, throttled: true) }
    }

    // reaching the boundary is what finishes a chapter, not landing on its last
    // page - a page can be the last one on screen without ever being read past.
    //
    // the engine's count is the fallback because a chapter crossed fast enough
    // may have had no page reported at all, and keying the total off `reached`
    // alone dropped those chapters silently
    private func complete(_ chapter: ReaderChapter, pages: Int) async {
        let id = ChapterRecord.ID(rawValue: chapter.id)
        let total = reached[id]?.total ?? pages
        guard total > 0 else { return }

        reached[id] = (total - 1, total)
        await save(id, throttled: false)
        await record(chapter)
    }

    // the reading event is independent of the progress save above: the save's
    // monotonic guard skips a re-read of a finished chapter, but a re-read
    // completion is still a reading act and today's tally counts acts. the
    // engine's completed set already makes this once per chapter per sitting
    private func record(_ chapter: ReaderChapter) async {
        engine?.setEvent(.recording, for: chapter.id)

        do {
            try await database.writer.write { [seriesId, seriesTitle] db in
                var event = ReadingEventRecord(
                    kind: .chapterCompleted,
                    seriesId: seriesId,
                    seriesTitle: seriesTitle,
                    chapterNumber: chapter.number
                )
                try event.insert(db)
            }
            sessionChaptersRead += 1
            engine?.setEvent(.recorded, for: chapter.id)
        } catch {
            // nothing landed, so the badge says nothing rather than lying
            engine?.setEvent(nil, for: chapter.id)
            AppLog.shared.log("failed to record reading event — \(error)", category: "reader")
        }
    }

    // inserted complete or not at all: a sitting that read nothing writes no
    // row, and a force-quit loses only the in-flight sitting - the same tail
    // the 3-second throttle already accepts
    private func endSession() async {
        guard let start = sessionStart else { return }
        sessionStart = nil

        let pages = reached.reduce(0) { sum, item in
            sum + max(0, item.value.page - (entered[item.key] ?? 0))
        }
        let chapters = sessionChaptersRead
        guard pages > 0 || chapters > 0 else { return }

        do {
            try await database.writer.write { [seriesId, seriesTitle] db in
                var session = ReadingSessionRecord(
                    seriesId: seriesId,
                    seriesTitle: seriesTitle,
                    pagesRead: pages,
                    chaptersRead: chapters,
                    startedDate: start,
                    endedDate: .now
                )
                try session.insert(db)
            }
        } catch {
            AppLog.shared.log("failed to record reading session — \(error)", category: "reader")
        }
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
        guard let number = numbers[id] else { return }

        do {
            try await database.writer.write { [seriesId] db in
                // written to every row carrying this number, not just the one being
                // read - the fraction is what transfers between sources, and it is
                // what (page + 1) / total already stores
                try ChapterRecord.apply(
                    progress: progress,
                    readDate: .now,
                    toNumbers: [number],
                    in: seriesId,
                    db: db
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

    // every row rather than the winners, so a slot carries what else could fill
    // it. rank stays out of the WHERE and goes into the ORDER BY instead, which
    // is what lets group() build options in ranking order in a single pass
    nonisolated private static func slotRows(
        for seriesId: SeriesRecord.ID,
        in db: Database
    ) throws -> [ChapterSlot.Row] {
        let sql = """
            SELECT
                c.id AS id,
                c.\(ChapterRecord.Columns.originId.name) AS originId,
                c.\(ChapterRecord.Columns.number.name) AS number,
                c.\(ChapterRecord.Columns.title.name) AS title,
                c.\(ChapterRecord.Columns.publishedDate.name) AS publishedDate,
                c.\(ChapterRecord.Columns.progress.name) AS progress,
                c.\(ChapterRecord.Columns.language.name) AS language,
                c.\(ChapterRecord.Columns.path.name) AS path,
                sc.\(ScanlatorRecord.Columns.name.name) AS scanlator,
                src.\(SourceRecord.Columns.slug.name) AS sourceSlug,
                src.\(SourceRecord.Columns.name.name) AS sourceName
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(BestChapterView.databaseTableName) bc ON bc.chapterId = c.id
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            JOIN \(ScanlatorRecord.databaseTableName) sc ON sc.id = c.\(ChapterRecord.Columns.scanlatorId.name)
            LEFT JOIN \(SourceRecord.databaseTableName) src ON src.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE bc.seriesId = ?
              AND bc.isVisible = 1
            ORDER BY bc.number ASC, bc.rank ASC
            """

        return try ChapterSlot.Row.fetchAll(db, sql: sql, arguments: [seriesId.rawValue])
    }
}

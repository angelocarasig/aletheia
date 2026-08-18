//
//  ReaderEngine.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class ReaderEngine {
    private let window: ChapterWindow
    private let chapters: [ReaderChapter]
    // only ever the share sheet's header - the engine is deliberately ignorant
    // of the series otherwise
    private let series: String
    private let boundaries: [ReaderChapter.ID: ReaderBoundaryInfo]
    private var loading: Set<ReaderChapter.ID> = []

    // a depth counter, not a flag: preload's detached Task can still be in
    // flight when a jump begins. while it is non-zero the reader is being
    // rebuilt, and a proximity request raised by clear()'s contentSize collapse
    // would resolve against a `current` that has not caught up yet - which is
    // what spliced the chapter *before* the one being opened above it
    private var navigating = 0

    private var resident: Set<ReaderChapter.ID> = []
    private var failures: [ReaderChapter.ID: ReaderError] = [:]

    // one-way, per chapter, per session: scrolling backward across a boundary
    // is a re-read, and an explicit jump clears the collection view rather than
    // scrolling across anything, so neither can mark a chapter finished
    private var completed: Set<ReaderChapter.ID> = []

    private var events: [ReaderChapter.ID: ReaderSeparatorModel.EventStatus] = [:]

    private var completable = false

    private var trackers: [ReaderSeparatorModel.Tracker] = []

    // and what each of them did about ONE finished chapter, keyed by chapter and
    // then by service. per chapter rather than per series, because the queue
    // clears for the series: without this, finishing chapter 45 would send
    // chapter 44's row back to spinning
    private var trackerStates: [ReaderChapter.ID: [String: ReaderSeparatorModel.Tracker.State]] =
        [:]

    @ObservationIgnored private weak var controller: ReaderController?

    private(set) var configuration: ReaderConfiguration
    private(set) var current: ReaderChapter?
    private(set) var page = 0
    private(set) var pageCount = 0
    private(set) var isLoading = false
    private(set) var isScrolling = false
    private(set) var isZoomed = false
    private(set) var isAutoScrolling = false
    // 1 → 0 across one dwell, what the countdown bar draws. paged modes only
    private(set) var autoAdvanceProgress: Double = 1
    private(set) var error: ReaderError?

    // fired once per chapter change, never on first load. the flag says whether
    // the reader jumped deliberately or simply scrolled into it
    var onChapterChanged: ((ReaderChapter, Bool) -> Void)?
    var onPageChanged: ((ReaderChapter, Int, Int) -> Void)?
    // fired once per chapter, forward only. carries the chapter's page count
    // because a chapter can be crossed without any of its pages ever being
    // reported visible, leaving the host no total to write progress against
    var onChapterFinished: ((ReaderChapter, Int) -> Void)?
    var onSingleTap: ((CGPoint) -> Void)?
    // the reader offered the end-of-list mark and it was taken. the host owns
    // the write and pushes the new answer back through setCompletable
    var onMarkCompleted: (() -> Void)?
    var onExplainGap: ((ReaderSeparatorModel.Gap) -> Void)?
    // the image never comes through here - the controller owns UIKit, so it
    // does the write and this carries only the answer
    var onPageSaved: ((Result<Void, Error>) -> Void)?
    var onRetryTracker: ((ReaderChapter.ID, String) -> Void)?

    var chapterList: [ReaderChapter] { chapters }

    var canGoPrevious: Bool {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }) else {
            return false
        }
        return index > 0
    }

    var canGoNext: Bool {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }) else {
            return false
        }
        return index < chapters.count - 1
    }

    init(
        chapters: [ReaderChapter],
        series: String = "",
        boundaries: [ReaderChapter.ID: ReaderBoundaryInfo] = [:],
        source: any ReaderPageSource,
        configuration: ReaderConfiguration
    ) {
        self.chapters = chapters
        self.series = series
        self.boundaries = boundaries
        self.configuration = configuration
        self.window = ChapterWindow(
            source: source,
            order: chapters.map(\.id),
            limit: configuration.windowSize
        )
    }

    // MARK: Lifecycle

    func attach(_ controller: ReaderController) {
        self.controller = controller
        controller.setOrder(chapters.map(\.id))

        controller.onVisiblePageChanged = { [weak self] page, index, total in
            self?.handleVisiblePage(page, index: index, total: total)
        }
        controller.onNeedsChapter = { [weak self] position in
            self?.preload(position)
        }
        controller.onSingleTap = { [weak self] point in
            self?.onSingleTap?(point)
        }
        controller.onZoomChanged = { [weak self] zoomed in
            self?.isZoomed = zoomed
        }
        controller.onScrollingChanged = { [weak self] scrolling in
            self?.isScrolling = scrolling
        }
        controller.onAutoScrollEnded = { [weak self] in
            self?.isAutoScrolling = false
            self?.autoAdvanceProgress = 1
        }
        controller.onAutoAdvanceProgress = { [weak self] progress in
            self?.autoAdvanceProgress = progress
        }
        controller.onCanContinue = { [weak self] in
            self?.canGoNext ?? false
        }
        controller.shareCaption = { [weak self] id in
            guard let self else { return nil }
            let number = chapters.first { $0.id == id }?.number
            return (series, number.map { "Chapter \($0.formatted())" } ?? "")
        }
        controller.onSaved = { [weak self] result in
            self?.onPageSaved?(result)
        }
        controller.separatorModel = { [weak self] boundary, direction in
            self?.separator(for: boundary, direction: direction)
                ?? ReaderSeparatorModel(
                    boundary: boundary, direction: direction, destination: .caughtUp)
        }
        controller.onSeparatorReached = { [weak self] boundary, direction in
            self?.reachedBoundary(boundary, direction: direction)
        }
        controller.onSeparatorComplete = { [weak self] in
            self?.onMarkCompleted?()
        }
        controller.onSeparatorGap = { [weak self] gap in
            self?.onExplainGap?(gap)
        }
        controller.onSeparatorRetry = { [weak self] boundary in
            guard case .after(let chapter) = boundary else { return }
            Task { await self?.retryNext(after: chapter) }
        }
        controller.onSeparatorRetryTracker = { [weak self] boundary, service in
            guard case .after(let chapter) = boundary else { return }
            self?.onRetryTracker?(chapter, service)
        }
    }

    func open(_ chapter: ReaderChapter.ID, progress: Double?) async {
        guard let target = chapters.first(where: { $0.id == chapter }) else {
            error = .notFound(chapter)
            return
        }

        isLoading = true
        navigating += 1
        defer { isLoading = false }

        do {
            let load = try await window.load(chapter)

            // asserted before the rebuild, not after: clear/apply can clamp the
            // offset and wake proximity, and anything that reads `current` in
            // that window must see the chapter being opened
            current = target
            pageCount = load.pages.count
            page = Self.startingPage(progress: progress, of: load.pages.count)

            await controller?.apply(load.pages, for: chapter)
            resident.insert(chapter)

            controller?.scroll(to: chapter, page: page, animated: false)
            error = nil
        } catch {
            self.error = Self.reason(from: error, chapter: chapter)
        }

        // re-armed explicitly once `current` is correct, so neighbours arrive in
        // a deterministic order rather than off whatever proximity fired mid-rebuild
        navigating -= 1
        preload(.end)
        preload(.start)
    }

    func jump(to chapter: ReaderChapter.ID) async {
        guard let target = chapters.first(where: { $0.id == chapter }) else { return }
        guard target.id != current?.id else { return }

        isLoading = true
        navigating += 1
        defer { isLoading = false }

        do {
            let load = try await window.load(chapter)
            await window.clear(keeping: chapter)

            // before clear(): emptying the snapshot collapses contentSize, the
            // scroll view clamps, and proximity fires with both edges "near".
            // with `current` already the target that request is at least honest,
            // and the navigating gate drops it outright
            let previous = current
            current = target
            pageCount = load.pages.count
            page = 0

            await controller?.clear()
            resident = []
            await controller?.apply(load.pages, for: chapter)
            resident.insert(chapter)

            controller?.scroll(to: chapter, page: 0, animated: false)
            error = nil

            if previous != nil {
                onChapterChanged?(target, true)
            }
        } catch {
            self.error = Self.reason(from: error, chapter: chapter)
        }

        navigating -= 1
        preload(.end)
        preload(.start)
    }

    // the scroll at the end is not a nicety: remove() deliberately declines to
    // compensate the offset when the item under the reader is inside the chapter
    // being removed, which is exactly this case, so apply() then prepends against
    // an offset nobody corrected
    func reload(_ chapter: ReaderChapter.ID) async {
        guard chapters.contains(where: { $0.id == chapter }) else { return }

        let isCurrent = chapter == current?.id
        let restore = isCurrent ? page : 0

        isLoading = true
        navigating += 1
        defer { isLoading = false }

        await window.evict(chapter)
        await controller?.remove(chapter)
        resident.remove(chapter)

        do {
            let load = try await window.load(chapter)
            await controller?.apply(load.pages, for: chapter)
            resident.insert(chapter)
            failures[chapter] = nil

            if let evicted = load.evicted {
                await controller?.remove(evicted)
                resident.remove(evicted)
            }

            if isCurrent {
                // a different source rarely splits a chapter into the same number
                // of pages, so the page being restored may not exist any more.
                // current is re-asserted too - a reload never changed it, but
                // nothing else guarantees it survived the remove/apply pair
                current = chapters.first { $0.id == chapter } ?? current
                pageCount = load.pages.count
                page = min(restore, max(0, load.pages.count - 1))
                controller?.scroll(to: chapter, page: page, animated: false)
            }

            controller?.reloadSeparators()
            error = nil
        } catch {
            self.error = Self.reason(from: error, chapter: chapter)
        }

        navigating -= 1
        preload(.end)
        preload(.start)
    }

    func previousChapter() async {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }),
            index > 0
        else { return }
        await jump(to: chapters[index - 1].id)
    }

    func nextChapter() async {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }),
            index < chapters.count - 1
        else { return }
        await jump(to: chapters[index + 1].id)
    }

    func goToPage(_ index: Int) {
        guard let current else { return }
        page = min(max(0, index), max(0, pageCount - 1))
        controller?.scroll(to: current.id, page: page, animated: false)
    }

    func advance(forward: Bool) {
        controller?.advance(by: forward ? 1 : -1)
        // moving by hand says "not yet" to the countdown rather than ending it
        controller?.resetAutoAdvance()
    }

    func retry() async {
        guard let chapter = error?.chapter else { return }
        error = nil
        await open(chapter, progress: nil)
    }

    // MARK: Configuration

    func update(_ value: ReaderConfiguration) {
        configuration = value
        controller?.update(value)
    }

    // MARK: Auto-scroll

    func toggleAutoScroll() {
        if isAutoScrolling {
            controller?.stopAutoScroll()
            isAutoScrolling = false
            autoAdvanceProgress = 1
        } else {
            controller?.startAutoScroll()
            isAutoScrolling = true
        }
    }

    // MARK: Private

    private func handleVisiblePage(_ visible: ReaderPage, index: Int, total: Int) {
        // a navigator has already asserted the chapter and page it is moving to,
        // and its own scroll(to:) reports on the way there. those reports are
        // geometrically honest but describe a position being passed through, so
        // letting them write would undo the destination the navigator just set
        guard navigating == 0 else { return }

        page = index
        pageCount = total

        guard let chapter = chapters.first(where: { $0.id == visible.chapter }) else { return }
        onPageChanged?(chapter, index, total)

        guard chapter.id != current?.id else { return }
        let hadChapter = current != nil
        current = chapter

        Task { await window.touch(chapter.id) }

        if hadChapter {
            onChapterChanged?(chapter, false)
        }
    }

    // MARK: Boundaries

    private func separator(
        for boundary: ReaderBoundary,
        direction: ReadingDirection
    ) -> ReaderSeparatorModel {
        switch boundary {
        case .start:
            return ReaderSeparatorModel(
                boundary: boundary,
                direction: direction,
                destination: .startOfSeries
            )

        case .after(let id):
            let info = boundaries[id] ?? .none
            let chapter = chapters.first { $0.id == id }
            let terminal = chapter.map {
                ReaderSeparatorModel.Terminal(number: $0.number, title: $0.title)
            }

            return ReaderSeparatorModel(
                boundary: boundary,
                direction: direction,
                terminal: terminal,
                continuity: info.continuity,
                gap: info.gap,
                destination: destination(after: id),
                event: events[id],
                crossed: completed.contains(id),
                completable: completable,
                trackers: trackerRows(for: id)
            )
        }
    }

    func setCompletable(_ value: Bool) {
        guard completable != value else { return }
        completable = value
        controller?.reloadSeparators()
    }

    func setEvent(_ status: ReaderSeparatorModel.EventStatus?, for chapter: ReaderChapter.ID) {
        guard events[chapter] != status else { return }
        events[chapter] = status
        controller?.reloadSeparators()
    }

    // called once while the reader is opening, before anything has been laid
    // out - a separator built before this lands would be the wrong height for
    // the rest of the session
    func setTrackers(_ value: [ReaderSeparatorModel.Tracker]) {
        guard trackers != value else { return }
        trackers = value
        controller?.reloadSeparators()
    }

    func setTrackerState(
        _ state: ReaderSeparatorModel.Tracker.State,
        for chapter: ReaderChapter.ID,
        service: String
    ) {
        guard trackerStates[chapter]?[service] != state else { return }
        trackerStates[chapter, default: [:]][service] = state
        controller?.reloadSeparators()
    }

    // default is skipped, not loading - a spinner would claim work that was
    // never asked for on a boundary the reader hasn't crossed yet
    private func trackerRows(for chapter: ReaderChapter.ID) -> [ReaderSeparatorModel.Tracker] {
        guard !trackers.isEmpty else { return [] }

        let states = trackerStates[chapter] ?? [:]
        return trackers.map { row in
            var resolved = row
            resolved.state = states[row.id] ?? .skipped
            return resolved
        }
    }

    private func destination(after id: ReaderChapter.ID) -> ReaderSeparatorModel.Destination {
        guard let slot = chapters.firstIndex(where: { $0.id == id }),
            slot < chapters.count - 1
        else { return .caughtUp }

        let next = chapters[slot + 1]

        if let failure = failures[next.id] { return .failed(failure) }
        if resident.contains(next.id) {
            return .chapter(number: next.number, title: next.title)
        }
        return .loading(number: next.number)
    }

    private func reachedBoundary(_ boundary: ReaderBoundary, direction: ReadingDirection) {
        // reaching the boundary is what finishes a chapter - a last page can be
        // on screen without ever being read past
        if case .after(let id) = boundary,
            direction == .forward,
            completed.insert(id).inserted,
            let chapter = chapters.first(where: { $0.id == id })
        {
            // the crossing itself turns the indicators on, and the writes that
            // follow may take a moment to report
            controller?.reloadSeparators()
            onChapterFinished?(chapter, controller?.pageCount(for: id) ?? 0)
        }

        // the boundary is the last item while its destination has not landed,
        // so proximity may already have re-armed. asking again is idempotent
        preload(direction == .forward ? .end : .start)
    }

    private func retryNext(after id: ReaderChapter.ID) async {
        guard let slot = chapters.firstIndex(where: { $0.id == id }),
            slot < chapters.count - 1
        else { return }

        failures[chapters[slot + 1].id] = nil
        controller?.reloadSeparators()
        preload(.end)
    }

    private func preload(_ position: ReaderController.Position) {
        // dropped rather than deferred: the navigator re-arms both directions on
        // its way out, once `current` is the chapter actually being read
        guard navigating == 0 else { return }
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }) else {
            return
        }

        let target: ReaderChapter?
        switch position {
        case .end: target = index < chapters.count - 1 ? chapters[index + 1] : nil
        case .start: target = index > 0 ? chapters[index - 1] : nil
        }

        // resident, not just the window: the cache holds bytes, the controller
        // holds sections, and the two drift apart on every evict and reload.
        // asking only the cache is what re-applied a chapter the collection view
        // still had, which is a duplicate section identifier and a hard crash
        guard let target, !loading.contains(target.id), !resident.contains(target.id) else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard await !self.window.isLoaded(target.id) else { return }

            self.loading.insert(target.id)
            // defer, not a trailing removal: a throw would skip the cleanup and
            // a chapter that failed once could never be preloaded again
            defer { self.loading.remove(target.id) }

            do {
                let load = try await self.window.load(target.id)
                await self.controller?.apply(load.pages, for: target.id)
                self.resident.insert(target.id)
                self.failures[target.id] = nil
                if let evicted = load.evicted {
                    await self.controller?.remove(evicted)
                    self.resident.remove(evicted)
                }
                self.controller?.reloadSeparators()
            } catch {
                // recorded, not just logged - otherwise the boundary can only
                // ever say "loading" and never "this failed, try again"
                self.failures[target.id] = Self.reason(from: error, chapter: target.id)
                self.controller?.reloadSeparators()
                AppLog.shared.log(
                    "preload failed for chapter \(target.id) - \(error)",
                    level: .error,
                    category: "reader"
                )
            }
        }
    }

    private static func reason(from error: Error, chapter: ReaderChapter.ID) -> ReaderError {
        if let error = error as? ReaderError { return error }
        if let error = error as? NetworkError, case .offline = error { return .offline(chapter) }
        return .fetchFailed(chapter, reason: Failure(error, fallback: "Failed to Load").sentence)
    }

    // progress is written as (page + 1) / total, so the inverse takes one back
    // off. a finished or untouched chapter opens at the start rather than
    // dumping the reader on the last page they already read
    static func startingPage(progress: Double?, of total: Int) -> Int {
        guard let progress, progress > 0, progress < 1, total > 0 else { return 0 }
        let page = Int((progress * Double(total)).rounded(.down)) - 1
        return min(max(0, page), total - 1)
    }
}

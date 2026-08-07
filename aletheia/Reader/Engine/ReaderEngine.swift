//
//  ReaderEngine.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import Observation

// owns what is on screen and decides what to load next. the controller owns
// UIKit and reports; nothing calls back the other way except through here.
//
// state is @Observable rather than an AsyncStream of transitions - v2 shipped
// seventeen states, one of them unreachable, and an error case whose recovery
// payload was always nil
@MainActor
@Observable
final class ReaderEngine {
    private let window: ChapterWindow
    private let chapters: [ReaderChapter]
    private var loading: Set<ReaderChapter.ID> = []

    @ObservationIgnored private weak var controller: ReaderController?

    private(set) var configuration: ReaderConfiguration
    private(set) var current: ReaderChapter?
    private(set) var page = 0
    private(set) var pageCount = 0
    private(set) var isLoading = false
    private(set) var isScrolling = false
    private(set) var isZoomed = false
    private(set) var isAutoScrolling = false
    private(set) var error: ReaderError?

    // fired once per chapter change, never on first load. the flag says whether
    // the reader jumped deliberately or simply scrolled into it
    var onChapterChanged: ((ReaderChapter, Bool) -> Void)?
    var onPageChanged: ((ReaderChapter, Int, Int) -> Void)?
    var onSingleTap: ((CGPoint) -> Void)?

    var chapterList: [ReaderChapter] { chapters }

    var canGoPrevious: Bool {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }) else { return false }
        return index > 0
    }

    var canGoNext: Bool {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }) else { return false }
        return index < chapters.count - 1
    }

    init(
        chapters: [ReaderChapter],
        source: any ReaderPageSource,
        configuration: ReaderConfiguration
    ) {
        self.chapters = chapters
        self.configuration = configuration
        self.window = ChapterWindow(source: source, limit: configuration.windowSize)
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
        }
    }

    func open(_ chapter: ReaderChapter.ID, progress: Double?) async {
        guard let target = chapters.first(where: { $0.id == chapter }) else {
            error = .notFound(chapter)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let load = try await window.load(chapter)
            await controller?.apply(load.pages, for: chapter)

            current = target
            pageCount = load.pages.count
            page = Self.startingPage(progress: progress, of: load.pages.count)
            controller?.scroll(to: chapter, page: page, animated: false)
            error = nil

            // a one-page chapter never scrolls far enough to trip proximity, so
            // its neighbours would never arrive on their own
            if load.pages.count == 1 {
                preload(.end)
                preload(.start)
            }
        } catch {
            self.error = Self.reason(from: error, chapter: chapter)
        }
    }

    func jump(to chapter: ReaderChapter.ID) async {
        guard let target = chapters.first(where: { $0.id == chapter }) else { return }
        guard target.id != current?.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let load = try await window.load(chapter)
            await window.clear(keeping: chapter)
            await controller?.clear()
            await controller?.apply(load.pages, for: chapter)

            let previous = current
            current = target
            pageCount = load.pages.count
            page = 0
            controller?.scroll(to: chapter, page: 0, animated: false)
            error = nil

            if previous != nil {
                onChapterChanged?(target, true)
            }
        } catch {
            self.error = Self.reason(from: error, chapter: chapter)
        }
    }

    func previousChapter() async {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }), index > 0 else { return }
        await jump(to: chapters[index - 1].id)
    }

    func nextChapter() async {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }),
              index < chapters.count - 1 else { return }
        await jump(to: chapters[index + 1].id)
    }

    func goToPage(_ index: Int) {
        guard let current else { return }
        page = min(max(0, index), max(0, pageCount - 1))
        controller?.scroll(to: current.id, page: page, animated: false)
    }

    func advance(forward: Bool) {
        controller?.advance(by: forward ? 1 : -1)
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
        } else {
            controller?.startAutoScroll()
            isAutoScrolling = true
        }
    }

    // MARK: Private

    private func handleVisiblePage(_ visible: ReaderPage, index: Int, total: Int) {
        page = index
        pageCount = total

        guard let chapter = chapters.first(where: { $0.id == visible.chapter }) else { return }
        onPageChanged?(chapter, index, total)

        guard chapter.id != current?.id else { return }
        let hadChapter = current != nil
        current = chapter

        // the chapter being read is the one worth keeping when the window has
        // to evict something
        Task { await window.touch(chapter.id) }

        if hadChapter {
            onChapterChanged?(chapter, false)
        }
    }

    private func preload(_ position: ReaderController.Position) {
        guard let current, let index = chapters.firstIndex(where: { $0.id == current.id }) else { return }

        let target: ReaderChapter?
        switch position {
        case .end: target = index < chapters.count - 1 ? chapters[index + 1] : nil
        case .start: target = index > 0 ? chapters[index - 1] : nil
        }

        guard let target, !loading.contains(target.id) else { return }

        Task { [weak self] in
            guard let self else { return }
            guard await !self.window.isLoaded(target.id) else { return }

            self.loading.insert(target.id)
            // defer, not a trailing removal: v2 threw past its own cleanup and
            // a chapter that failed once could never be preloaded again
            defer { self.loading.remove(target.id) }

            do {
                let load = try await self.window.load(target.id)
                await self.controller?.apply(load.pages, for: target.id)
                if let evicted = load.evicted {
                    await self.controller?.remove(evicted)
                }
            } catch {
                AppLog.shared.log(
                    "preload failed for chapter \(target.id) — \(error)",
                    category: "reader"
                )
            }
        }
    }

    private static func reason(from error: Error, chapter: ReaderChapter.ID) -> ReaderError {
        if let error = error as? ReaderError { return error }
        if let error = error as? NetworkError, case .offline = error { return .offline(chapter) }
        return .fetchFailed(chapter, reason: error.localizedDescription)
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

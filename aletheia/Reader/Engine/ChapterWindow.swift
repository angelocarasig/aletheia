//
//  ChapterWindow.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// holds page urls for the few chapters around the reader and nothing else. a
// decoded page is ~11mb, so the whole series can never be resident - only urls
// are, and those are a few kilobytes per chapter.
//
// single-flight is a task map rather than v2's array of continuations: a second
// caller awaits the same task, cancellation comes free, and there is no way to
// leak a continuation on the error path
actor ChapterWindow {
    private let source: any ReaderPageSource
    private let limit: Int

    private var pages: [ReaderChapter.ID: [ReaderPage]] = [:]
    private var recency: [ReaderChapter.ID] = []
    private var inFlight: [ReaderChapter.ID: Task<[ReaderPage], Error>] = [:]

    struct Load: Sendable {
        let pages: [ReaderPage]
        let evicted: ReaderChapter.ID?
    }

    init(source: any ReaderPageSource, limit: Int) {
        self.source = source
        self.limit = max(1, limit)
    }

    func load(_ id: ReaderChapter.ID) async throws -> Load {
        if let cached = pages[id] {
            touch(id)
            return Load(pages: cached, evicted: nil)
        }

        if let running = inFlight[id] {
            return Load(pages: try await running.value, evicted: nil)
        }

        let task = Task<[ReaderPage], Error> { [source] in
            let fetched = try await source.pages(for: id)
            guard !fetched.isEmpty else { throw ReaderError.noPages(id) }
            return fetched
        }
        inFlight[id] = task

        do {
            let fetched = try await task.value
            inFlight[id] = nil
            pages[id] = fetched
            touch(id)
            return Load(pages: fetched, evicted: evictIfNeeded(protecting: id))
        } catch {
            // a failed fetch is never cached, so a retry actually retries
            inFlight[id] = nil
            throw error
        }
    }

    func cached(_ id: ReaderChapter.ID) -> [ReaderPage]? {
        pages[id]
    }

    func isLoaded(_ id: ReaderChapter.ID) -> Bool {
        pages[id] != nil
    }

    // in eviction order, oldest first
    func loaded() -> [ReaderChapter.ID] {
        recency
    }

    // the chapter being read is not necessarily the one most recently loaded -
    // preloading a neighbour makes it look older than it is. v2 never did this,
    // so reading backwards could evict the page on screen
    func touch(_ id: ReaderChapter.ID) {
        guard pages[id] != nil else { return }
        recency.removeAll { $0 == id }
        recency.append(id)
    }

    func evict(_ id: ReaderChapter.ID) {
        pages[id] = nil
        recency.removeAll { $0 == id }
    }

    func clear(keeping keep: ReaderChapter.ID? = nil) {
        let survivor = keep.flatMap { id in pages[id].map { (id, $0) } }
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        pages.removeAll()
        recency.removeAll()

        if let survivor {
            pages[survivor.0] = survivor.1
            recency = [survivor.0]
        }
    }

    // MARK: Private

    private func evictIfNeeded(protecting keep: ReaderChapter.ID) -> ReaderChapter.ID? {
        guard recency.count > limit else { return nil }
        guard let victim = recency.first(where: { $0 != keep }) else { return nil }
        evict(victim)
        return victim
    }
}

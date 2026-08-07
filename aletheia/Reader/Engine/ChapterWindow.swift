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

    // reading order, so eviction can pick by distance from where the reader
    // actually is rather than by how long ago something was touched
    private let slots: [ReaderChapter.ID: Int]

    private var pages: [ReaderChapter.ID: [ReaderPage]] = [:]
    private var current: ReaderChapter.ID?
    private var inFlight: [ReaderChapter.ID: Task<[ReaderPage], Error>] = [:]

    struct Load: Sendable {
        let pages: [ReaderPage]
        let evicted: ReaderChapter.ID?
    }

    init(source: any ReaderPageSource, order: [ReaderChapter.ID], limit: Int) {
        self.source = source
        self.limit = max(1, limit)
        self.slots = Dictionary(
            uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) }
        )
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

    func loaded() -> [ReaderChapter.ID] {
        pages.keys.sorted { (slots[$0] ?? 0) < (slots[$1] ?? 0) }
    }

    // says which chapter is being read, which is what eviction measures from.
    // not the most recently loaded - preloading a neighbour would claim that
    func touch(_ id: ReaderChapter.ID) {
        guard pages[id] != nil else { return }
        current = id
    }

    func evict(_ id: ReaderChapter.ID) {
        pages[id] = nil
        if current == id { current = nil }
    }

    func clear(keeping keep: ReaderChapter.ID? = nil) {
        let survivor = keep.flatMap { id in pages[id].map { (id, $0) } }
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        pages.removeAll()
        current = nil

        if let survivor {
            pages[survivor.0] = survivor.1
            current = survivor.0
        }
    }

    // MARK: Private

    // the chapter furthest from the one being read goes. recency only picked
    // the right victim by accident: touch fires on chapter change, so scrolling
    // back and forth scrambled it, and it never knew about reading distance.
    //
    // reading forward this still evicts behind the reader; reading backward it
    // now evicts ahead, where removal shifts nothing on screen
    private func evictIfNeeded(protecting keep: ReaderChapter.ID) -> ReaderChapter.ID? {
        guard pages.count > limit else { return nil }

        let anchor = slots[current ?? keep] ?? 0
        let victim = pages.keys
            .filter { $0 != keep && $0 != current }
            .sorted { a, b in
                let da = abs((slots[a] ?? 0) - anchor)
                let db = abs((slots[b] ?? 0) - anchor)
                // on a tie prefer the one behind: forward is the common
                // direction of travel, so what is ahead is worth more
                return da == db ? (slots[a] ?? 0) < (slots[b] ?? 0) : da > db
            }
            .first

        guard let victim else { return nil }
        evict(victim)
        return victim
    }
}

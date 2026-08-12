//
//  ReaderPages.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import CoreGraphics
import Foundation

// a page carries its own headers because a series can hold origins from
// different sources, so what makes an image load - referer, the pinned agent,
// whatever cookies that site needs - is a property of the chapter it came from
// rather than of the reader.
//
// `size` is what the source already knew about the page's shape, and it spares
// the reader a guess. absent, the reader estimates and corrects on load
struct ReaderPage: Identifiable, Hashable, Sendable {
    let chapter: ReaderChapter.ID
    let index: Int
    let url: URL
    let headers: [String: String]
    let size: CGSize?

    var id: Self { self }

    init(
        chapter: ReaderChapter.ID,
        index: Int,
        url: URL,
        headers: [String: String] = [:],
        size: CGSize? = nil
    ) {
        self.chapter = chapter
        self.index = index
        self.url = url
        self.headers = headers
        self.size = size
    }
}

// identity is hand-written to EXCLUDE size and headers, and that is
// load-bearing. this type is the diffable data source's item identifier, so if
// size took part a dimension arriving late would make the page a different
// item - diffing as a remove plus an insert, tearing the cell down and
// reloading its image. headers are out for the same reason with more teeth: a
// credential refresh rewrites the Cookie on every page at once.
//
// a page is the same page whatever we have since learned about its shape
extension ReaderPage {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chapter == rhs.chapter && lhs.index == rhs.index && lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chapter)
        hasher.combine(index)
        hasher.combine(url)
    }
}

// everything the reader lays out. a separator is a real item rather than a
// floating overlay, so it scrolls with the content and takes part in the same
// geometry as the pages either side of it
enum ReaderItem: Hashable, Sendable {
    case page(ReaderPage)
    case separator(ReaderBoundary)

    var page: ReaderPage? {
        guard case let .page(page) = self else { return nil }
        return page
    }
}

// identity is the boundary itself, never the direction of travel or anything
// else that changes. the same reasoning as ReaderPage.size above: a separator
// whose identity moved would diff as a remove plus an insert every time you
// approached it from the other side
enum ReaderBoundary: Hashable, Sendable {
    case start
    case after(ReaderChapter.ID)
}

// which way the reader is travelling through the chapter list. derived from
// reading order rather than screen coordinates - right-to-left mirrors the
// layout and each mode has its own axis, so coordinates cannot answer this
enum ReadingDirection: Sendable {
    case forward
    case backward
}

// the host's single obligation. everything else the engine does is local.
protocol ReaderPageSource: Sendable {
    func pages(for chapter: ReaderChapter.ID) async throws -> [ReaderPage]
}

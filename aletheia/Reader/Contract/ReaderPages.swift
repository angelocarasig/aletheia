//
//  ReaderPages.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import CoreGraphics
import Foundation

// a page carries its own referer because a series can hold origins from
// different sources, so the header that makes an image load is a property of
// the chapter it came from rather than of the reader.
//
// `size` is what the source already knew about the page's shape, and it spares
// the reader a guess. absent, the reader estimates and corrects on load
struct ReaderPage: Identifiable, Hashable, Sendable {
    let chapter: ReaderChapter.ID
    let index: Int
    let url: URL
    let referer: URL?
    let size: CGSize?

    var id: Self { self }

    init(chapter: ReaderChapter.ID, index: Int, url: URL, referer: URL?, size: CGSize? = nil) {
        self.chapter = chapter
        self.index = index
        self.url = url
        self.referer = referer
        self.size = size
    }
}

// identity is hand-written to EXCLUDE size, and that is load-bearing. this type
// is the diffable data source's item identifier, so if size took part a
// dimension arriving late would make the page a different item - diffing as a
// remove plus an insert, tearing the cell down and reloading its image.
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

// the host's single obligation. everything else the engine does is local.
protocol ReaderPageSource: Sendable {
    func pages(for chapter: ReaderChapter.ID) async throws -> [ReaderPage]
}

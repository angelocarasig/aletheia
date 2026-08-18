//
//  ReaderPages.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import CoreGraphics
import Foundation

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

// identity excludes size and headers deliberately: this is the diffable data
// source's item identifier, so either taking part would diff a late-arriving
// value as remove+insert, tearing the cell down and reloading its image -
// headers especially, since a credential refresh rewrites every page's Cookie
// at once
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

enum ReaderItem: Hashable, Sendable {
    case page(ReaderPage)
    case separator(ReaderBoundary)

    var page: ReaderPage? {
        guard case .page(let page) = self else { return nil }
        return page
    }
}

// identity is the boundary alone, never direction - same diffable-identity
// reasoning as ReaderPage above
enum ReaderBoundary: Hashable, Sendable {
    case start
    case after(ReaderChapter.ID)
}

// derived from reading order, not screen coordinates - RTL and vertical modes
// each mirror a different axis, so coordinates can't answer this
enum ReadingDirection: Sendable {
    case forward
    case backward
}

protocol ReaderPageSource: Sendable {
    func pages(for chapter: ReaderChapter.ID) async throws -> [ReaderPage]
}

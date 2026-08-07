//
//  ChapterFill.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import Tagged

// which row is currently serving a chapter number. the engine holds one id per
// chapter for its whole life and never learns that anything moved - this sits in
// front of the fetch and points it somewhere else.
//
// empty means every chapter is served by whatever best_chapter ranked first, so
// a reader with no swaps behaves exactly as it did before this existed.
//
// an actor because ChapterWindow loads chapters concurrently - the next chapter
// is being fetched while the current one is being read, and both come through
// SeriesPageSource
actor ChapterFill {
    // keyed by the engine's chapter token, which is the rank-1 row id at open.
    // an entry only exists where the reader has chosen something else
    private var rows: [ReaderChapter.ID: ChapterRecord.ID] = [:]

    func row(for chapter: ReaderChapter.ID) -> ChapterRecord.ID {
        rows[chapter] ?? ChapterRecord.ID(rawValue: chapter)
    }

    // choosing the chapter's own default row clears the entry rather than storing
    // it, so "swapped" always means "not what ranking would have given you"
    func set(_ row: ChapterRecord.ID, for chapter: ReaderChapter.ID) {
        rows[chapter] = row.rawValue == chapter ? nil : row
    }

    func isSwapped(_ chapter: ReaderChapter.ID) -> Bool {
        rows[chapter] != nil
    }

    func clear() {
        rows.removeAll()
    }
}

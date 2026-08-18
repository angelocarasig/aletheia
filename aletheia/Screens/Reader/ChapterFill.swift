//
//  ChapterFill.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import Tagged

actor ChapterFill {
    private var rows: [ReaderChapter.ID: ChapterRecord.ID] = [:]

    func row(for chapter: ReaderChapter.ID) -> ChapterRecord.ID {
        rows[chapter] ?? ChapterRecord.ID(rawValue: chapter)
    }

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

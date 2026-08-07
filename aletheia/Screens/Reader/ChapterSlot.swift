//
//  ChapterSlot.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import GRDB
import SwiftUI
import Tagged

// one point on the series' number line, and everything able to fill it. this is
// the shape both reader sheets read: the chapter list draws one row per slot and
// the source switcher draws that slot's options.
//
// grouping by number rather than by row is the whole point - a series is a number
// line, and which origin currently wins a number is a ranking answer that moves
struct ChapterSlot: Identifiable, Hashable, Sendable {
    let number: Double
    // ranked the way best_chapter ranks them: origin priority, then scanlator
    // priority, then id. never empty - a slot exists because a row filled it
    let options: [Option]

    var id: Double { number }

    var best: Option { options[0] }

    // what the engine is keyed on. the reader takes a bare Int64 slot token, so
    // the row id is unwrapped here rather than at every call site
    var chapter: ReaderChapter.ID { best.id.rawValue }

    // read state belongs to the number, so it is resolved here rather than per
    // option. max, not best.progress, because rows written before read state
    // propagated by number can still disagree with each other
    var progress: Double {
        options.map(\.progress).max() ?? 0
    }

    var finished: Bool { progress >= 1 }

    var started: Bool { progress > 0 && progress < 1 }

    // more than one thing can serve this number, so the switcher has something
    // to offer. the button is pointless when it can only show what you have
    var hasAlternatives: Bool { options.count > 1 }

    struct Option: Identifiable, Hashable, Sendable {
        let id: ChapterRecord.ID
        let originId: OriginRecord.ID
        let title: String
        let scanlator: String
        let language: LanguageCode
        let publishedDate: Date
        let progress: Double

        // the source's own identity, so the switcher can group options under it.
        // both nil together when the origin has been disconnected from its source
        let sourceName: String?
        let sourceIcon: ImageResource?
    }
}

// MARK: - Building

extension ChapterSlot {
    // the flat shape the query returns, one per chapter row. ordering is the
    // caller's job: rows must arrive number-ascending, rank-ascending within a
    // number, so grouping is one pass and options keep their ranking
    struct Row: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let originId: Int64
        let number: Double
        let title: String
        let scanlator: String
        let language: LanguageCode
        let publishedDate: Date
        let progress: Double
        let sourceSlug: String?
        let sourceName: String?
    }

    // icons resolve here rather than at render: an ImageResource lookup per row
    // per redraw is waste, and a slot is built once per sheet
    static func group(_ rows: [Row], icon: (String) -> ImageResource?) -> [ChapterSlot] {
        var slots: [ChapterSlot] = []
        var current: (number: Double, options: [Option])?

        for row in rows {
            let option = Option(
                id: ChapterRecord.ID(rawValue: row.id),
                originId: OriginRecord.ID(rawValue: row.originId),
                title: row.title,
                scanlator: row.scanlator,
                language: row.language,
                publishedDate: row.publishedDate,
                progress: row.progress,
                sourceName: row.sourceName,
                sourceIcon: row.sourceSlug.flatMap(icon)
            )

            if var open = current, open.number == row.number {
                open.options.append(option)
                current = open
            } else {
                if let open = current {
                    slots.append(ChapterSlot(number: open.number, options: open.options))
                }
                current = (row.number, [option])
            }
        }

        if let open = current {
            slots.append(ChapterSlot(number: open.number, options: open.options))
        }

        return slots
    }
}

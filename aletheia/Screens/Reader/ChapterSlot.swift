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

struct ChapterSlot: Identifiable, Hashable, Sendable {
    let number: Double
    let options: [Option]

    var id: Double { number }

    var best: Option { options[0] }

    var chapter: ReaderChapter.ID { best.id.rawValue }

    // max, not best.progress - rows written before read state propagated by
    // number can still disagree with each other
    var progress: Double {
        options.map(\.progress).max() ?? 0
    }

    var finished: Bool { progress >= 1 }

    var started: Bool { progress > 0 && progress < 1 }

    var hasAlternatives: Bool { options.count > 1 }

    struct Option: Identifiable, Hashable, Sendable {
        let id: ChapterRecord.ID
        let originId: OriginRecord.ID
        let title: String
        let scanlator: String
        let language: LanguageCode
        let publishedDate: Date
        let progress: Double

        // path is stamped only on completion, so an in-flight download reads as
        // not downloaded; slot is a snapshot, built once per sheet open
        let downloaded: Bool

        let sourceName: String?
        let sourceIcon: ImageResource?
    }
}

// MARK: - Building

extension ChapterSlot {
    // caller must supply rows number-ascending, rank-ascending within a number -
    // grouping is a single pass and relies on that order
    struct Row: Decodable, FetchableRecord, Sendable {
        let id: Int64
        let originId: Int64
        let number: Double
        let title: String
        let scanlator: String
        let language: LanguageCode
        let publishedDate: Date
        let progress: Double
        let path: String?
        let sourceSlug: String?
        let sourceName: String?
    }

    // resolved here rather than at render, to avoid a lookup per row per redraw
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
                downloaded: row.path != nil,
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

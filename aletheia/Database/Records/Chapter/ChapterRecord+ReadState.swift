//
//  ChapterRecord+ReadState.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import GRDB
import Tagged

// read state belongs to a chapter NUMBER, not to the one row that happens to win
// best_chapter today. a series is a number line and any origin may fill any point
// on it, so writing progress to a single row means that the moment ranking moves -
// a source disabled, origins reordered, a per-session source switch - everything
// you have read comes back unread and the library's counts jump.
//
// every read-state write goes through here so no caller has to remember that
extension ChapterRecord {
    static func apply(
        progress: Double? = nil,
        readDate: Date? = nil,
        toNumbers numbers: [Double],
        in seriesId: SeriesRecord.ID,
        monotonic: Bool = true,
        db: Database
    ) throws {
        guard !numbers.isEmpty else { return }

        var assignments: [ColumnAssignment] = []
        if let progress { assignments.append(Columns.progress.set(to: progress)) }
        if let readDate { assignments.append(Columns.lastReadDate.set(to: readDate)) }
        guard !assignments.isEmpty else { return }

        let origins = try OriginRecord
            .filter(OriginRecord.Columns.seriesId == seriesId.rawValue)
            .select(OriginRecord.Columns.id, as: OriginRecord.ID.self)
            .fetchAll(db)
        guard !origins.isEmpty else { return }

        // numbers compare as stored doubles. two sources spelling the same chapter
        // "52.5" parse to the same value, so equality holds without rounding
        var request = ChapterRecord
            .filter(origins.contains(Columns.originId))
            .filter(numbers.contains(Columns.number))

        // a sibling row can already be further along than the one being written -
        // reading source B after source A must not undo A. clearing read state is
        // the only caller allowed to move progress backwards
        if monotonic, let progress {
            request = request.filter(Columns.progress < progress)
        }

        try request.updateAll(db, assignments)
    }
}

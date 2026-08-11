//
//  SeriesRecord+ReadState.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Tagged

// stamping a read date and moving the status are one fact, so they are one call
// in one transaction. every caller that records reading goes through here for
// the same reason ChapterRecord.apply exists - so nobody has to remember the
// second half
extension SeriesRecord {
    static func markRead(_ seriesId: SeriesRecord.ID, at date: Date, db: Database) throws {
        // reading is what the act says, so anything that is not already saying it
        // gets moved: planned, paused and dropped are all answers a page turn
        // contradicts. two exemptions, both because the write would say nothing -
        // reading is already the answer, and completed outranks it, since a
        // reread does not un-finish a series you finished
        _ = try SeriesRecord
            .filter(key: seriesId.rawValue)
            .filter(Columns.status != Status.reading.rawValue)
            .filter(Columns.status != Status.completed.rawValue)
            .updateAll(db, Columns.status.set(to: Status.reading.rawValue))

        // written whether or not the series is in the library: the launch purge
        // spares anything carrying a read date
        _ = try SeriesRecord
            .filter(key: seriesId.rawValue)
            .updateAll(db, Columns.lastReadDate.set(to: date))

        // a linked service owns the same fact remotely and has to be told, but
        // the request cannot happen in here - a write held open across a network
        // call blocks every other writer. so the intent is recorded on the link
        // and drained outside, which is also what makes an offline read catch up
        // later rather than being lost
        try SeriesTrackerRecord.enqueue(for: seriesId, status: .reading, in: db)
    }
}

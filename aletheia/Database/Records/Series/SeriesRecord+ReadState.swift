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
        // TODO: sync with trackers here. the move below is the local half of
        // "you are reading this" - a linked tracker owns the same fact
        // remotely and has to be told, and its answer may disagree (a service
        // that already says Completed must not be pushed back to Reading). the
        // push cannot happen inside this transaction: it is network work, and a
        // write held open across it blocks every other writer. record the intent
        // here and drain it outside, so a failed or offline push retries rather
        // than rolling back a read the user actually did.

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
    }
}

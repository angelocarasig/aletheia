//
//  SeriesTrackerRecord+Sync.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Tagged

// the local half of a push. everything here runs inside somebody else's
// transaction: recording that a link is dirty is part of the same fact as the
// read that dirtied it, while the request itself happens outside, because a
// write held open across a network call blocks every other writer
extension SeriesTrackerRecord {
    // where the reader has got to, as one integer, across every origin.
    //
    // read state belongs to a chapter NUMBER here and is written across origins,
    // so any mapping that is a function of rows - best_chapter's rank, a
    // per-origin scope - silently changes its answer when the reader reorders
    // their sources. hence flat against chapter joined to origin, max rather than
    // count, and floored. see docs/features/trackers.md §8
    static func furthest(for seriesId: SeriesRecord.ID, in db: Database) throws -> Int {
        let highest =
            try Double.fetchOne(
                db,
                sql: """
                    SELECT MAX(c.\(ChapterRecord.Columns.number.name))
                    FROM \(ChapterRecord.databaseTableName) c
                    JOIN \(OriginRecord.databaseTableName) o
                      ON o.\(OriginRecord.Columns.id.name) = c.\(ChapterRecord.Columns.originId.name)
                    WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
                      AND c.\(ChapterRecord.Columns.progress.name) >= 1
                    """, arguments: [seriesId.rawValue]) ?? 0

        return max(0, Int(highest.rounded(.down)))
    }

    // called by every path that records reading
    static func enqueue(for seriesId: SeriesRecord.ID, status: Status? = nil, in db: Database)
        throws
    {
        let links =
            try SeriesTrackerRecord
            .filter(Columns.seriesId == seriesId.rawValue)
            .fetchAll(db)

        guard !links.isEmpty else { return }

        let progress = try furthest(for: seriesId, in: db)

        for var link in links where !link.isInert {
            // monotonic in the column as well as at the wire: a sibling row can
            // already be ahead, and the drain may not have run yet
            let pending = max(progress, link.pendingProgress ?? 0)
            let advances = pending > link.remoteProgress && pending != link.pendingProgress
            // a service calling the work finished outranks a re-read, the same
            // exemption markRead applies locally. only the automatic promotion
            // passes through here - an explicit edit writes to the service
            // directly and is allowed to say whatever the reader picked
            let finished = link.remoteStatus == .completed
            let moves =
                !finished
                && (status.map { $0 != link.remoteStatus && $0 != link.pendingStatus } ?? false)

            // nothing to say is not a write. the row was being touched on every
            // page turn regardless, and each touch wakes the queue observation
            guard advances || moves else { continue }

            if advances { link.pendingProgress = pending }
            if moves { link.pendingStatus = status }

            try link.update(db)
        }
    }

    // scoped to one service, because that is the unit the drain walks: a lane
    // paces itself against its own rate limit and halts on its own dead token
    static func dirty(for tracker: Tracker? = nil, in db: Database) throws -> [SeriesTrackerRecord]
    {
        var request =
            SeriesTrackerRecord
            .filter(Columns.pendingProgress != nil || Columns.pendingStatus != nil)

        if let tracker {
            request = request.filter(Columns.tracker == tracker.rawValue)
        }

        return try request.order(Columns.attemptedDate).fetchAll(db)
    }
}

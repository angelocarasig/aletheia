//
//  LiveTrackerImportSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// the real MigrationSource for a tracker restore - one call through the
// compositor, which owns the token and the retry-once-on-reauth policy.
// fixed to one tracker at construction time - the setup screen resolves
// which before building this, only ever for one that actually conforms to
// BulkListingTracker (trackers.list(_:) throws .unavailable otherwise)
struct LiveTrackerImportSource: MigrationSource {
    let tracker: Tracker

    private let trackers: Compositor.Trackers

    init(tracker: Tracker, trackers: Compositor.Trackers) {
        self.tracker = tracker
        self.trackers = trackers
    }

    func fetch() async throws -> [TrackerImportEntry] {
        let list = try await trackers.list(tracker)
        return list.map {
            TrackerImportEntry(
                id: $0.remoteId,
                title: $0.title,
                cover: $0.cover,
                progress: $0.progress,
                remoteStatus: $0.status ?? "",
                totalChapters: $0.totalChapters
            )
        }
    }
}

//
//  LiveTrackerImportSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

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

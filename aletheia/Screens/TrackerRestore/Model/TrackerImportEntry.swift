//
//  TrackerImportEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation
import Tagged

// one row of a tracker's list, before anything local exists for it. never
// persisted - this is session-only working data, gone the moment the screen
// closes unless it was Saved
struct TrackerImportEntry: MigrationEntry {
    let id: Int64
    let title: String
    let cover: URL?
    let progress: Int
    // the source tracker's own raw status string ("CURRENT" on AniList,
    // "plan_to_read" on MyAnimeList, ...) - kept raw rather than pre-mapped,
    // since a restore session pulls from exactly one tracker and that
    // vocabulary is only known at commit time (Status.init?(raw:for:) in
    // TrackerRestoreCommitting.swift)
    let remoteStatus: String
    let totalChapters: Int?

    // a tracker's list describes what is out there, not what is already in
    // the library - Save always has to resolve or mint the series itself
    var existingSeriesId: SeriesRecord.ID? { nil }
}

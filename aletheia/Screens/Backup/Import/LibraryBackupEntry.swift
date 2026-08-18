//
//  LibraryBackupEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import Tagged

// one series from a decoded backup. existingSeriesId is always nil - a
// backup entry describes what a series was at export time, not a series
// this run already knows about locally, so the commit chain resolves or
// mints it the same way tracker restore does (an (sourceId, slug) origin
// lookup, not an assumption)
//
// v1 restores one origin per series - the lowest-priority ("primary") one
// among whatever the backup carried - the same one-origin-per-entry shape
// every other migration flow in this app already uses. any additional
// origins the series had at export time are not restored
struct LibraryBackupEntry: MigrationEntry {
    let id: Int
    let title: String
    var cover: URL? { nil }
    var existingSeriesId: SeriesRecord.ID? { nil }

    let seriesEntry: LibraryBackup.SeriesEntry
    let primaryOrigin: LibraryBackup.SeriesEntry.OriginEntry?
    // known ahead of time when primaryOrigin's source is still installed -
    // lets the row skip live search entirely (MigrationComposer's
    // initialMatch), the "no search needed at all" fast path
    // docs/features/library-backup.md §5 calls for
    let resolvedCandidate: MigrationCandidate?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

//
//  SourceMigrationEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import Tagged

// one series already in the library that needs a new origin - either moving
// off a source deliberately (source migration) or because its old one is
// gone (disconnected migration). the two flows share this one entry shape
// and one commit chain; only the query that finds them differs
// (SeriesOnSourceMigrationSource vs DisconnectedOriginMigrationSource)
struct SourceMigrationEntry: MigrationEntry {
    // the origin being replaced - doubles as the row's identity (it is
    // already unique) and as what the commit chain copies progress from and,
    // in .migrate mode, removes
    let id: OriginRecord.ID
    let seriesId: SeriesRecord.ID
    let title: String
    let cover: URL?

    // always known - this flow never creates a series, only attaches a new
    // origin to one that is already in the library
    var existingSeriesId: SeriesRecord.ID? { seriesId }
}

// what happens to the old origin once the new one is confirmed working.
// both put the new origin at top priority - that is the point of running
// this at all, whether or not the old one is kept
enum OriginMigrationMode: String, CaseIterable, Identifiable {
    case migrate
    case copy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .migrate: "Migrate"
        case .copy: "Copy"
        }
    }

    var summary: String {
        switch self {
        case .migrate: "Move to the new source and remove the old one."
        case .copy: "Add the new source and keep the old one as a fallback."
        }
    }
}

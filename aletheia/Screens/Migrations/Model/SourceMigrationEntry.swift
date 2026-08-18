//
//  SourceMigrationEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import Tagged

struct SourceMigrationEntry: MigrationEntry {
    // doubles as row identity and as what the commit chain copies progress
    // from and, in .migrate mode, removes
    let id: OriginRecord.ID
    let seriesId: SeriesRecord.ID
    let title: String
    let cover: URL?

    var existingSeriesId: SeriesRecord.ID? { seriesId }
}

// both modes put the new origin at top priority
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

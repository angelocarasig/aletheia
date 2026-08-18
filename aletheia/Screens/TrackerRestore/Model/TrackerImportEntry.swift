//
//  TrackerImportEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation
import Tagged

struct TrackerImportEntry: MigrationEntry {
    let id: Int64
    let title: String
    let cover: URL?
    let progress: Int
    let remoteStatus: String
    let totalChapters: Int?

    var existingSeriesId: SeriesRecord.ID? { nil }
}

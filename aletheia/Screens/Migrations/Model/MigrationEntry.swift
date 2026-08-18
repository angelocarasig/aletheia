//
//  MigrationEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import Tagged

// nil existingSeriesId means Save may mint a new series (tracker restore,
// file import); a non-nil id means Save only ever attaches a new origin,
// never creates (source migration, disconnected-source migration)
protocol MigrationEntry: Identifiable, Sendable, Hashable {
    var title: String { get }
    var cover: URL? { get }
    var existingSeriesId: SeriesRecord.ID? { get }
}

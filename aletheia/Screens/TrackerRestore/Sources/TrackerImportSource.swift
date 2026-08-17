//
//  TrackerImportSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// one tracker's whole list, pulled once. LiveTrackerImportSource is the real
// implementation, generic over any tracker whose service opts into
// BulkListingTracker
protocol TrackerImportSource: Sendable {
    var tracker: Tracker { get }
    func fetchLibrary() async throws -> [TrackerImportEntry]
}

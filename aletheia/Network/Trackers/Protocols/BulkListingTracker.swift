//
//  BulkListingTracker.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// all three services happen to conform today, but the base TrackerService
// contract still has no bulk method - a future tracker without one works
// everywhere except restore
protocol BulkListingTracker: TrackerService {
    func list(token: String) async throws -> [TrackerListEntry]
}

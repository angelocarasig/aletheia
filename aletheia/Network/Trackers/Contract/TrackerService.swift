//
//  TrackerService.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// stateless - every call takes the access token rather than reaching for it,
// which keeps the authority and the services from depending on each other
protocol TrackerService: Sendable {
    var tracker: Tracker { get }

    func viewer(token: String) async throws -> TrackerViewer
    func search(_ query: String, adult: Bool, token: String) async throws -> [TrackerCandidate]
    // "not on your list yet" is an ordinary answer, not an error - an unlisted
    // entry comes back with isListed false
    func entry(remoteId: Int64, token: String) async throws -> TrackerEntry
    func save(_ update: TrackerUpdate, token: String) async throws -> TrackerEntry
    func delete(_ entry: TrackerEntry, token: String) async throws
}

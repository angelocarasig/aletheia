//
//  TrackerService.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// one list service, stateless. every call takes the access token rather than
// reaching for it, which is what keeps the authority and the services from
// depending on each other in both directions
protocol TrackerService: Sendable {
    var tracker: Tracker { get }

    func viewer(token: String) async throws -> TrackerViewer
    func search(_ query: String, adult: Bool, token: String) async throws -> [TrackerCandidate]
    // one call for the media and the reader's entry on it together, because
    // "not on your list yet" is an ordinary answer rather than an error and the
    // media exists either way. an unlisted entry comes back with isListed false
    func entry(remoteId: Int64, token: String) async throws -> TrackerEntry
    func save(_ update: TrackerUpdate, token: String) async throws -> TrackerEntry
    func delete(_ entry: TrackerEntry, token: String) async throws
}

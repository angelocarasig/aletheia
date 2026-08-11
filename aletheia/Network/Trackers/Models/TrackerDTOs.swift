//
//  TrackerDTOs.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

struct TrackerViewer: Sendable, Equatable {
    let id: Int64
    let name: String
    var avatar: URL?
    var scoreFormat: ScoreFormat = .point10
}

// a search result. enough per row to separate a sequel from its parent at a
// glance, which is the whole job of the link sheet
struct TrackerCandidate: Sendable, Hashable, Identifiable {
    let id: Int64
    let title: String
    var cover: URL?
    var year: Int?
    var totalChapters: Int?
    var status: Publication = .Unknown
    var adult: Bool = false
    // the two facts that separate a series from its own sequel when the titles
    // do not: who made it, and what it is about
    var authors: String?
    var synopsis: String?
    // manga, novel, one-shot. linking a light novel entry to the manga is the
    // classic misfire, and it is the one mistake nothing else on a row catches -
    // same title, same author, same year, same cover art
    var format: String?
}

// what the service says about one media, plus your entry on it if you have one
struct TrackerEntry: Sendable, Equatable {
    let remoteId: Int64
    let title: String
    var totalChapters: Int?
    // the same display facts a search result carries, so an entry opened from a
    // linked row renders as fully as one opened from a search
    var cover: URL?
    var year: Int?
    var authors: String?
    var synopsis: String?
    var format: String?
    var publication: Publication = .Unknown
    var adult: Bool = false

    // nil means the media is not on your list. every other field below is then
    // meaningless and the caller is expected to seed rather than compare
    var entryId: Int64?
    var status: Status?
    var progress: Int = 0
    // canonical 0...100 whatever the account displays
    var score: Int?

    var isListed: Bool { entryId != nil || status != nil }

    // what a search row would have shown for the same media
    var candidate: TrackerCandidate {
        TrackerCandidate(
            id: remoteId,
            title: title,
            cover: cover,
            year: year,
            totalChapters: totalChapters,
            status: publication,
            adult: adult,
            authors: authors,
            synopsis: synopsis,
            format: format
        )
    }
}

// a sparse patch. nil means leave it alone - both services preserve an omitted
// field, and a blind full-object write is what moves list positions and resets
// statuses on services that have no idea you did not mean to
struct TrackerUpdate: Sendable, Equatable {
    let remoteId: Int64
    var entryId: Int64?
    var progress: Int?
    var status: Status?
    var score: Int?
    var startDate: Date?
}

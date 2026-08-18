//
//  TrackerDTOs.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// no remote user id here - one was carried for a while and read by nothing, and
// the third service's is a string rather than a number, so the field was
// deleted rather than widened. see docs/features/tracker-mangabaka.md §7.1
struct TrackerViewer: Sendable, Equatable {
    let name: String
    var avatar: URL?
    var scoreFormat: ScoreFormat = .point10
}

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

    // this is a comic reader, so a novel entry is a legitimate pick and almost
    // never the right one. the string is the service's own word - anilist filters
    // NOVEL out of its query entirely, mal says "Novel"/"Light novel" and
    // mangabaka "Novel"/"Light_novel" - so a contains match covers all of them
    var isNovel: Bool {
        format?.localizedCaseInsensitiveContains("novel") ?? false
    }
}

struct TrackerEntry: Sendable, Equatable {
    let remoteId: Int64
    let title: String
    var totalChapters: Int?
    var cover: URL?
    var year: Int?
    var authors: String?
    var synopsis: String?
    var format: String?
    var publication: Publication = .Unknown
    var adult: Bool = false

    // what a linked service contributes to the series itself, as one supplier
    // among the sources. empty when the service has nothing to say - never a
    // guess, and never Safe by omission
    var titles: [String] = []
    var covers: [URL] = []
    var tags: [String] = []
    var classification: Classification = .Unknown

    // nil means the media is not on your list. every other field below is then
    // meaningless and the caller is expected to seed rather than compare
    var entryId: Int64?
    var status: Status?
    var progress: Int = 0
    // canonical 0...100 whatever the account displays
    var score: Int?

    var isListed: Bool { entryId != nil || status != nil }

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

// one row of a bulk list pull - BulkListingTracker's own shape, distinct from
// TrackerEntry because it never carries the extra lookup (synopsis, tags,
// covers) a single-media fetch does. a caller maps this to whatever it needs
struct TrackerListEntry: Sendable, Equatable {
    let remoteId: Int64
    let title: String
    var cover: URL?
    var totalChapters: Int?
    var progress: Int = 0
    // the service's own raw status string ("CURRENT", "PLANNING", ...), not
    // pre-mapped - Tracker Restore's commit step is where a fresh series'
    // initial Status gets decided, and that decision belongs at commit time
    var status: String?
    var adult: Bool = false
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

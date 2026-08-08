//
//  LibraryFilter.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation
import Tagged

// an empty set means "not filtering on this", never "match nothing" - the two
// read the same in a Set and only one of them is ever what someone meant.
//
// groups are ANDed and options within a group are ORed, which is what every
// filter panel does and what people expect without being told: reading OR
// planning, AND ongoing
struct LibraryFilter: Equatable, Codable {
    var statuses: Set<Status> = []
    var publications: Set<Publication> = []
    var classifications: Set<Classification> = []
    var readStates: Set<ReadState> = []

    // by id, not by name: a tag renamed upstream keeps the filter pointing at the
    // same tag, and a deleted one drops out on its own
    var tags: Set<TagRecord.ID> = []
    var sources: Set<SourceRecord.ID> = []

    // rowids are positive and autoincrementing, so a negative one can never
    // collide with a real source. stands for "this series has an origin whose
    // source is gone" - a state worth filtering for, and the only one that has
    // no row to name it
    static let detachedSource = SourceRecord.ID(rawValue: -1)

    var isActive: Bool {
        count > 0
    }

    var count: Int {
        statuses.count
            + publications.count
            + classifications.count
            + readStates.count
            + tags.count
            + sources.count
    }

    func matches(_ entry: LibraryViewModel.Entry) -> Bool {
        if !statuses.isEmpty, !statuses.contains(entry.status) {
            return false
        }

        if !readStates.isEmpty, !readStates.contains(where: { $0.matches(entry) }) {
            return false
        }

        // a series with no origins has nothing to compare, so any filter on
        // origin-owned metadata excludes it rather than letting it through
        if !publications.isEmpty {
            guard let publication = entry.publication, publications.contains(publication) else {
                return false
            }
        }

        if !classifications.isEmpty {
            guard let classification = entry.classification,
                  classifications.contains(classification)
            else { return false }
        }

        return true
    }

    // tags and sources are relationships, not columns on the row, so they are
    // matched against maps the view model holds rather than against the entry
    func matches(tagIDs: Set<TagRecord.ID>, sourceIDs: Set<SourceRecord.ID>) -> Bool {
        if !tags.isEmpty, tags.isDisjoint(with: tagIDs) {
            return false
        }

        if !sources.isEmpty, sources.isDisjoint(with: sourceIDs) {
            return false
        }

        return true
    }

    mutating func clear() {
        statuses = []
        publications = []
        classifications = []
        readStates = []
        tags = []
        sources = []
    }
}

// how far through it you are, which no single column answers - unread comes from
// the chapter count and started comes from a date
enum ReadState: String, CaseIterable, Codable {
    case unread
    case inProgress
    case finished

    var label: String {
        switch self {
        case .unread: "Unread"
        case .inProgress: "In Progress"
        case .finished: "Caught Up"
        }
    }

    func matches(_ entry: LibraryViewModel.Entry) -> Bool {
        switch self {
        case .unread: entry.lastReadDate == .distantPast
        case .inProgress: entry.lastReadDate > .distantPast && entry.unreadCount > 0
        case .finished: entry.unreadCount == 0
        }
    }

    static var ordered: [ReadState] {
        [.unread, .inProgress, .finished]
    }
}

// one toggle for all three groups, so the sheet never grows a per-group variant
extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}

// label, icon and tint already live on Status in DetailsActions
extension Status {
    // the order a series moves through, not alphabetical - the list reads as a
    // lifecycle and the one you are most likely to want sits first
    static var ordered: [Status] {
        [.reading, .planning, .paused, .completed, .dropped]
    }
}

extension Publication {
    var label: String {
        switch self {
        case .Unknown: "Unknown"
        case .Ongoing: "Ongoing"
        case .Completed: "Completed"
        case .Hiatus: "Hiatus"
        case .Cancelled: "Cancelled"
        }
    }

    // Unknown last: it is a gap in what a source told us, not a state a series
    // is in, so it should never lead the list
    static var ordered: [Publication] {
        [.Ongoing, .Hiatus, .Completed, .Cancelled, .Unknown]
    }
}

extension Classification {
    var label: String {
        switch self {
        case .Unknown: "Unrated"
        case .Safe: "Safe"
        case .Suggestive: "Suggestive"
        case .Explicit: "Explicit"
        }
    }

    static var ordered: [Classification] {
        [.Safe, .Suggestive, .Explicit, .Unknown]
    }
}

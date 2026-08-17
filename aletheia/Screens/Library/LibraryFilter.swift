//
//  LibraryFilter.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation
import Tagged
// for ImageResource - the tracker chips draw the service marks, and the type is
// generated into the asset symbol namespace rather than Foundation
import SwiftUI

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
    var trackers: Set<TrackerFilter> = []

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
            + trackers.count
    }

    // asOf rather than a date read in here: one recency option compares against
    // now, and a predicate that reads the clock itself answers differently for
    // each entry in the same pass
    func matches(_ entry: LibraryViewModel.Entry, asOf: Date) -> Bool {
        if !statuses.isEmpty, !statuses.contains(entry.status) {
            return false
        }

        if !readStates.isEmpty, !readStates.contains(where: { $0.matches(entry, asOf: asOf) }) {
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

    // tags, sources and trackers are relationships, not columns on the row, so
    // they are matched against maps the view model holds rather than against the
    // entry
    func matches(
        tagIDs: Set<TagRecord.ID>,
        sourceIDs: Set<SourceRecord.ID>,
        linked: Set<Tracker>
    ) -> Bool {
        if !tags.isEmpty, tags.isDisjoint(with: tagIDs) {
            return false
        }

        if !sources.isEmpty, sources.isDisjoint(with: sourceIDs) {
            return false
        }

        // ORed like every other group, which is what makes anilist + untracked
        // mean "linked there, or linked nowhere" rather than a contradiction
        if !trackers.isEmpty, !trackers.contains(where: { $0.matches(linked) }) {
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
        trackers = []
    }
}

// a link is a relationship, so this sits with tags and sources rather than with
// the column-backed groups. untracked is a real answer rather than the absence
// of one - "which of these have I never linked" is the question the group is
// most often opened for
enum TrackerFilter: Codable, Hashable {
    case linked(Tracker)
    case untracked

    var tracker: Tracker? {
        switch self {
        case let .linked(tracker): tracker
        case .untracked: nil
        }
    }

    var label: String {
        tracker?.name ?? "Not Linked"
    }

    // the service marks are template-rendered for surfaces that tint them; the
    // chip draws the full-colour tile, the same one the tracking rows use
    var artwork: ImageResource? {
        tracker.flatMap { ImageResource(name: $0.icon, bundle: .main) }
    }

    func matches(_ linked: Set<Tracker>) -> Bool {
        guard let tracker else { return linked.isEmpty }
        return linked.contains(tracker)
    }

    // every service, in the order Tracker declares them, then the negative case -
    // it is the odd one out and reads as a footnote to the list rather than a
    // peer. read off Tracker.allCases rather than written out: this was a
    // hand-kept copy of that enum, and mangabaka shipped 10/8 without ever
    // reaching the library filters because nobody remembered a third list existed
    static var ordered: [TrackerFilter] {
        Tracker.allCases.map(TrackerFilter.linked) + [.untracked]
    }
}

// stored as one string, so a filter saved before this was an enum with a payload
// still decodes. lowercased on the way in for the same reason - the two enums
// spelled myanimelist differently, and a reader's saved filters should not be
// dropped over a capital letter
extension TrackerFilter {
    private static let untrackedKey = "untracked"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == Self.untrackedKey {
            self = .untracked
        } else if let tracker = Tracker(rawValue: raw.lowercased()) {
            self = .linked(tracker)
        } else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "unknown tracker filter '\(raw)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tracker?.rawValue ?? Self.untrackedKey)
    }
}

// how far through it you are, which no single column answers - unread comes from
// the chapter count and started comes from a date
enum ReadState: String, CaseIterable, Codable {
    case unread
    case inProgress
    case finished
    case stale

    // long enough that a slow scanlation group is not caught by it, and not a
    // preference: it is read at match time, so moving it rewrites nothing
    private enum Rule {
        static let stale: TimeInterval = 60 * 24 * 60 * 60
    }

    var label: String {
        switch self {
        case .unread: "Unread"
        case .inProgress: "In Progress"
        case .finished: "Caught Up"
        case .stale: "Not Read Lately"
        }
    }

    func matches(_ entry: LibraryViewModel.Entry, asOf: Date) -> Bool {
        switch self {
        case .unread: entry.lastReadDate == .distantPast
        case .inProgress: entry.lastReadDate > .distantPast && entry.unreadCount > 0
        case .finished: entry.unreadCount == 0
        // only against a series still claiming Reading: a reader who said Set
        // Aside has already answered, and saying it back to them would be the
        // app disputing their own word. derived on read, so nothing is written
        // and being wrong costs a row in a list rather than a status
        case .stale:
            entry.status == .reading
                && entry.lastReadDate > .distantPast
                && asOf.timeIntervalSince(entry.lastReadDate) > Rule.stale
        }
    }

    static var ordered: [ReadState] {
        [.unread, .inProgress, .finished, .stale]
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

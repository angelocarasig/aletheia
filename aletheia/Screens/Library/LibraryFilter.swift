//
//  LibraryFilter.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation
import SwiftUI
import Tagged

struct LibraryFilter: Equatable, Codable {
    var statuses = TriSet<Status>()
    var publications = TriSet<Publication>()
    var classifications = TriSet<Classification>()
    var readStates: Set<ReadState> = []

    var tags = TriSet<TagRecord.ID>()
    var sources = TriSet<SourceRecord.ID>()
    var trackers = TriSet<TrackerFilter>()

    // sentinel for "series has an origin whose source no longer exists" - rowids
    // are positive, so -1 never collides with a real source
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

    // asOf is passed in rather than read here - a predicate that reads the clock
    // itself would answer differently for each entry in the same pass
    func matches(_ entry: LibraryViewModel.Entry, asOf: Date) -> Bool {
        if !statuses.matches(entry.status) {
            return false
        }

        if !readStates.isEmpty, !readStates.contains(where: { $0.matches(entry, asOf: asOf) }) {
            return false
        }

        if !publications.isEmpty {
            guard let publication = entry.publication, publications.matches(publication) else {
                return false
            }
        }

        if !classifications.isEmpty {
            guard let classification = entry.classification,
                classifications.matches(classification)
            else { return false }
        }

        return true
    }

    func matches(
        tagIDs: Set<TagRecord.ID>,
        sourceIDs: Set<SourceRecord.ID>,
        linked: Set<Tracker>
    ) -> Bool {
        if !tags.matchesAny(tagIDs) {
            return false
        }

        if !sources.matchesAny(sourceIDs) {
            return false
        }

        if !trackers.excluded.isEmpty, trackers.excluded.contains(where: { $0.matches(linked) }) {
            return false
        }

        if !trackers.included.isEmpty, !trackers.included.contains(where: { $0.matches(linked) }) {
            return false
        }

        return true
    }

    mutating func clear() {
        statuses = TriSet()
        publications = TriSet()
        classifications = TriSet()
        readStates = []
        tags = TriSet()
        sources = TriSet()
        trackers = TriSet()
    }
}

struct TriSet<Element: Hashable & Codable>: Equatable, Codable {
    var included: Set<Element> = []
    var excluded: Set<Element> = []

    enum State { case off, included, excluded }

    var isEmpty: Bool { included.isEmpty && excluded.isEmpty }
    var count: Int { included.count + excluded.count }

    func contains(_ element: Element) -> Bool {
        included.contains(element) || excluded.contains(element)
    }

    func state(for element: Element) -> State {
        if included.contains(element) { return .included }
        if excluded.contains(element) { return .excluded }
        return .off
    }

    mutating func cycle(_ element: Element) {
        if included.contains(element) {
            included.remove(element)
            excluded.insert(element)
        } else if excluded.contains(element) {
            excluded.remove(element)
        } else {
            included.insert(element)
        }
    }

    func matches(_ value: Element) -> Bool {
        if excluded.contains(value) { return false }
        if !included.isEmpty, !included.contains(value) { return false }
        return true
    }

    func matchesAny(_ values: Set<Element>) -> Bool {
        if !excluded.isDisjoint(with: values) { return false }
        if !included.isEmpty, included.isDisjoint(with: values) { return false }
        return true
    }
}

enum TrackerFilter: Codable, Hashable {
    case linked(Tracker)
    case untracked

    var tracker: Tracker? {
        switch self {
        case .linked(let tracker): tracker
        case .untracked: nil
        }
    }

    var label: String {
        tracker?.name ?? "Not Linked"
    }

    var artwork: ImageResource? {
        tracker.flatMap { ImageResource(name: $0.icon, bundle: .main) }
    }

    func matches(_ linked: Set<Tracker>) -> Bool {
        guard let tracker else { return linked.isEmpty }
        return linked.contains(tracker)
    }

    // derived from Tracker.allCases rather than hand-copied - a hand-kept copy
    // missed mangabaka's launch and dropped it from library filters
    static var ordered: [TrackerFilter] {
        Tracker.allCases.map(TrackerFilter.linked) + [.untracked]
    }
}

// lowercased because Tracker and the enum it replaced spelled myanimelist
// differently - dropping this would break already-saved filters
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

enum ReadState: String, CaseIterable, Codable {
    case unread
    case inProgress
    case finished
    case stale

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

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}

// label, icon, and tint live on Status in DetailsActions, not here
extension Status {
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

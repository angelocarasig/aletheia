//
//  LibrarySort.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// the raw values are persisted, so they are stable identifiers rather than
// display strings - renaming a label must never reset someone's choice
enum LibrarySort: String, CaseIterable, Identifiable {
    case added
    case updated
    case lastRead
    case title
    case unread

    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: "Date Added"
        case .updated: "Last Updated"
        case .lastRead: "Last Read"
        case .title: "Title"
        case .unread: "Unread"
        }
    }

    // one glyph per option, never a shared arrow - an arrow describes the
    // direction, which is the other control on the sheet
    var icon: String {
        switch self {
        case .added: "calendar.badge.plus"
        case .updated: "arrow.trianglehead.2.clockwise"
        case .lastRead: "book"
        case .title: "textformat"
        case .unread: "envelope.badge"
        }
    }

    // what ascending means differs per option, and saying it plainly is cheaper
    // than making someone try both. dates read newest-first when descending,
    // which is why every date option defaults that way
    func direction(ascending: Bool) -> String {
        switch self {
        case .title: ascending ? "A to Z" : "Z to A"
        case .unread: ascending ? "Fewest first" : "Most first"
        default: ascending ? "Oldest first" : "Newest first"
        }
    }

    var defaultsAscending: Bool {
        self == .title
    }

    func sort(_ entries: [LibraryViewModel.Entry], ascending: Bool) -> [LibraryViewModel.Entry] {
        let sorted: [LibraryViewModel.Entry]

        switch self {
        case .added: sorted = entries.sorted { $0.addedDate < $1.addedDate }
        case .updated: sorted = entries.sorted { $0.updatedDate < $1.updatedDate }
        case .lastRead: sorted = entries.sorted { $0.lastReadDate < $1.lastReadDate }
        case .unread: sorted = entries.sorted { $0.unreadCount < $1.unreadCount }
        case .title:
            sorted = entries.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }

        return ascending ? sorted : sorted.reversed()
    }
}

//
//  ReadStateTests.swift
//  aletheiaTests
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Testing
import Foundation
@testable import aletheia

// stale is the one filter option derived from the clock rather than a column, so
// it is the one whose answer cannot be read off the row. the cases below are the
// three it must never claim: a reader who already said Set Aside, a series never
// opened, and one read last week
@Suite("ReadState.stale")
struct ReadStateTests {

    private static let asOf = Date(timeIntervalSince1970: 1_770_000_000)

    private func entry(
        status: Status,
        lastRead: Date,
        unread: Int = 3
    ) -> LibraryViewModel.Entry {
        LibraryViewModel.Entry(
            id: .init(rawValue: 1),
            title: "Title",
            cover: nil,
            unreadCount: unread,
            status: status,
            publication: nil,
            classification: nil,
            addedDate: Self.asOf,
            updatedDate: Self.asOf,
            lastReadDate: lastRead
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        Self.asOf.addingTimeInterval(-Double(days) * 24 * 60 * 60)
    }

    @Test("matches a Reading series untouched past the threshold")
    func staleReading() {
        let stale = entry(status: .reading, lastRead: daysAgo(90))
        #expect(ReadState.stale.matches(stale, asOf: Self.asOf))
    }

    @Test("does not match a Reading series read recently")
    func recentReading() {
        let recent = entry(status: .reading, lastRead: daysAgo(7))
        #expect(!ReadState.stale.matches(recent, asOf: Self.asOf))
    }

    @Test("never disputes a status the reader set themselves", arguments: [
        Status.paused, .dropped, .completed, .planning
    ])
    func declaredStatus(_ status: Status) {
        let declared = entry(status: status, lastRead: daysAgo(365))
        #expect(!ReadState.stale.matches(declared, asOf: Self.asOf))
    }

    @Test("never matches a series that was never opened")
    func neverRead() {
        let fresh = entry(status: .reading, lastRead: .distantPast)
        #expect(!ReadState.stale.matches(fresh, asOf: Self.asOf))
        #expect(ReadState.unread.matches(fresh, asOf: Self.asOf))
    }
}

//
//  SeriesTrackerRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Tagged

// two rows if both services are linked, and they never consult each other - a
// failure on one is not a failure on the other, and neither arbitrates the
// other's numbers.
//
// the remote* columns are a deliberate copy of what the service last said. an
// offline or signed-out series still has to render "AniList - 44 of 240", and a
// keychain read is not something a list row should depend on.
// see docs/features/trackers.md §7
struct SeriesTrackerRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    private(set) var seriesId: SeriesRecord.ID
    private(set) var tracker: Tracker

    // the media id, which is what every read and write addresses
    private(set) var remoteId: Int64

    // the one case where a link's remote id may legitimately move: the service
    // merged this series into another and named the successor, which mangabaka
    // states outright and asks callers to follow. nothing else may move it - a
    // link otherwise points at exactly what the reader confirmed.
    // see docs/features/tracker-mangabaka.md §6.1
    mutating func adopt(remoteId: Int64) {
        self.remoteId = remoteId
    }
    // the list-entry id, which is a different number and is what a delete
    // targets. anilist hands it back from SaveMediaListEntry; myanimelist has no
    // such id and addresses the entry by media id alone
    var remoteEntryId: Int64?

    var remoteTitle: String
    var remoteStatus: Status?
    var remoteProgress: Int
    // canonical 0...100 regardless of what the account displays, so a reader
    // switching their anilist scale changes the drawing and not the data
    var remoteScore: Int?
    // null is ongoing or unknown. myanimelist's 0 sentinel normalises to null on
    // the way in, since both mean the same thing to a clamp
    var totalChapters: Int?

    // the queue. a push carries no payload worth keeping - it is always whatever
    // local state says at the moment it is sent - so there is nothing to record
    // but that this link is dirty
    var pendingProgress: Int?
    var pendingStatus: Status?

    var linkedDate: Date = .now
    var syncedDate: Date = .distantPast
    // stamped on every attempt, succeeded or not; syncError is the current
    // status half, nulled on success. same pair as origin, same no-history rule
    var attemptedDate: Date = .distantPast
    var syncError: String?

    var isDirty: Bool {
        pendingProgress != nil || pendingStatus != nil
    }

    var failing: Bool {
        syncError != nil
    }

    // an entry the service already calls finished is inert to automatic pushes:
    // there is no local rereading state to express, and anilist's REPEATING
    // zeroes remote progress server-side. only an explicit edit writes here
    var isInert: Bool {
        remoteStatus == .completed
    }

    init(
        seriesId: SeriesRecord.ID,
        tracker: Tracker,
        remoteId: Int64,
        remoteEntryId: Int64? = nil,
        remoteTitle: String,
        remoteStatus: Status? = nil,
        remoteProgress: Int = 0,
        remoteScore: Int? = nil,
        totalChapters: Int? = nil
    ) {
        self.id = nil
        self.seriesId = seriesId
        self.tracker = tracker
        self.remoteId = remoteId
        self.remoteEntryId = remoteEntryId
        self.remoteTitle = remoteTitle
        self.remoteStatus = remoteStatus
        self.remoteProgress = remoteProgress
        self.remoteScore = remoteScore
        self.totalChapters = totalChapters
    }
}

// MARK: - DatabaseRecord

extension SeriesTrackerRecord {
    static var databaseTableName: String {
        "series_tracker"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let tracker = Column(CodingKeys.tracker)

        static let remoteId = Column(CodingKeys.remoteId)
        static let remoteEntryId = Column(CodingKeys.remoteEntryId)
        static let remoteTitle = Column(CodingKeys.remoteTitle)
        static let remoteStatus = Column(CodingKeys.remoteStatus)
        static let remoteProgress = Column(CodingKeys.remoteProgress)
        static let remoteScore = Column(CodingKeys.remoteScore)
        static let totalChapters = Column(CodingKeys.totalChapters)

        static let pendingProgress = Column(CodingKeys.pendingProgress)
        static let pendingStatus = Column(CodingKeys.pendingStatus)

        static let linkedDate = Column(CodingKeys.linkedDate)
        static let syncedDate = Column(CodingKeys.syncedDate)
        static let attemptedDate = Column(CodingKeys.attemptedDate)
        static let syncError = Column(CodingKeys.syncError)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)

            // the cascade is correct here, unlike the download queue: a deleted
            // series has no pending push worth keeping
            t.belongsTo(SeriesRecord.databaseTableName, onDelete: .cascade)

            t.column(Columns.tracker.name, .text).notNull()

            t.column(Columns.remoteId.name, .integer).notNull()
            t.column(Columns.remoteEntryId.name, .integer)
            t.column(Columns.remoteTitle.name, .text).notNull()
            t.column(Columns.remoteStatus.name, .text)
            t.column(Columns.remoteProgress.name, .integer).notNull().defaults(to: 0)
            t.column(Columns.remoteScore.name, .integer)
            t.column(Columns.totalChapters.name, .integer)

            t.column(Columns.pendingProgress.name, .integer)
            t.column(Columns.pendingStatus.name, .text)

            t.column(Columns.linkedDate.name, .datetime).notNull()
            t.column(Columns.syncedDate.name, .datetime).notNull()
            t.column(Columns.attemptedDate.name, .datetime).notNull()
            t.column(Columns.syncError.name, .text)

            t.uniqueKey([Columns.seriesId.name, Columns.tracker.name])
        }
    }

    static func createIndexes(db: Database) throws {
        // the unique key above already covers reads keyed by series, so this is for the cascade
        try db.create(
            index: "idx_series_tracker_seriesId",
            on: databaseTableName,
            columns: [Columns.seriesId.name],
            ifNotExists: true
        )

        // reverse lookup - is this remote entry already linked to something
        try db.create(
            index: "idx_series_tracker_remote",
            on: databaseTableName,
            columns: [Columns.tracker.name, Columns.remoteId.name],
            ifNotExists: true
        )

        // partial index, same shape as idx_origin_failing - dirty rows are a
        // handful of the table at any moment
        try db.create(
            index: "idx_series_tracker_pending",
            on: databaseTableName,
            columns: [Columns.seriesId.name],
            options: .ifNotExists,
            condition: Columns.pendingProgress != nil
        )

        try db.create(
            index: "idx_series_tracker_failing",
            on: databaseTableName,
            columns: [Columns.seriesId.name],
            options: .ifNotExists,
            condition: Columns.syncError != nil
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Associations

extension SeriesTrackerRecord {
    static let series = belongsTo(SeriesRecord.self)

    var series: QueryInterfaceRequest<SeriesRecord> {
        request(for: SeriesTrackerRecord.series)
    }
}

extension SeriesRecord {
    static let trackers = hasMany(SeriesTrackerRecord.self)

    var trackers: QueryInterfaceRequest<SeriesTrackerRecord> {
        request(for: SeriesRecord.trackers)
    }
}

//
//  PanelBookmarkRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Foundation
import GRDB
import Tagged

struct PanelBookmarkRecord: Codable, DatabaseRecord {
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?

    // no foreign key on purpose - same soft-reference reasoning as
    // ReadingEventRecord/ReadingSessionRecord (see Aletheia.docc/Architecture/Schema.md
    // "History tables carry no foreign keys"). a bookmark has to survive a
    // "Reset Series" (DetailsComposer+Observation.swift resetSeries()), which
    // hard-deletes the series row and cascades away every origin and chapter
    // under it, then re-inserts fresh rows with new ids
    var seriesId: SeriesRecord.ID
    var seriesTitle: String

    // chapterNumber, not a chapterId - same reasoning ReadingEventRecord
    // already applies: a chapter's row id becomes permanently unresolvable
    // once deleted, but its number is a stable, source-derived value. if the
    // series is reset and its chapters re-fetched, a new chapter row with
    // the same number exists, so a best-effort join on (seriesId,
    // chapterNumber) has a real chance of reconnecting post-reset, where a
    // raw dangling chapterId never could
    var chapterNumber: Double
    var chapterTitle: String

    // which page within the chapter was bookmarked
    var index: Int

    // the bookmark's own saved copy of the page image - deliberately not a
    // reference into the chapter's own download folder, which can be swept
    // or deleted independent of a series reset and would take the bookmark
    // down with it. storage convention (folder layout, AssetStore
    // integration) is not decided yet - see TODO below
    var path: String

    var createdDate: Date = .now
}

// MARK: - DatabaseRecord

extension PanelBookmarkRecord {
    static var databaseTableName: String {
        "panel_bookmark"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let seriesId = Column(CodingKeys.seriesId)
        static let seriesTitle = Column(CodingKeys.seriesTitle)
        static let chapterNumber = Column(CodingKeys.chapterNumber)
        static let chapterTitle = Column(CodingKeys.chapterTitle)
        static let index = Column(CodingKeys.index)
        static let path = Column(CodingKeys.path)
        static let createdDate = Column(CodingKeys.createdDate)
    }

    static func createTable(db: Database) throws {
        try db.create(table: databaseTableName, options: [.ifNotExists]) { t in
            t.autoIncrementedPrimaryKey(Columns.id.name)
            t.column(Columns.seriesId.name, .integer).notNull()
            t.column(Columns.seriesTitle.name, .text).notNull()
            t.column(Columns.chapterNumber.name, .double).notNull()
            t.column(Columns.chapterTitle.name, .text).notNull()
            t.column(Columns.index.name, .integer).notNull()
            t.column(Columns.path.name, .text).notNull()
            t.column(Columns.createdDate.name, .datetime).notNull()
        }
    }

    static func createIndexes(db: Database) throws {
        try db.create(
            index: "idx_panel_bookmark_seriesId_chapterNumber",
            on: databaseTableName,
            columns: [Columns.seriesId.name, Columns.chapterNumber.name],
            ifNotExists: true
        )

        try db.create(
            index: "idx_panel_bookmark_createdDate",
            on: databaseTableName,
            columns: [Columns.createdDate.name],
            ifNotExists: true
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = ID(rawValue: inserted.rowID)
    }
}

// MARK: - Intent

// "panel bookmarks" - a reader context-menu option ("Bookmark Panel") that
// saves the current page's image so it can be replayed later in a dedicated
// view/list elsewhere in the app, independent of whether the series or
// chapter it came from still exists in a resolvable state. mainly meant for
// key pivotal moments a reader wants to hold onto, not a general screenshot
// tool - one bookmark is one specific page, not a range or a whole chapter.
//
// this table follows the same soft-reference shape ReadingEventRecord/
// ReadingSessionRecord already established for exactly this survival
// requirement (see the comments above and Schema.md's "History tables carry
// no foreign keys"): no FK on seriesId, a chapterNumber instead of a
// chapterId, and snapshot columns (seriesTitle/chapterTitle) so a row stays
// meaningful even when its best-effort join back to series/chapter fails.
// a series reset (DetailsComposer+Observation.swift resetSeries()) hard-
// deletes the series row and cascades away every origin and chapter under
// it via ON DELETE CASCADE, then re-inserts everything fresh with new ids -
// a bookmark has to read back correctly across that boundary, showing its
// saved image and snapshot text even when the join to a live chapter fails,
// and best-effort reconnecting via (seriesId, chapterNumber) when it can.
//
// TODO: this migration lands the schema only. still open, to be decided
// when the feature is actually implemented:
// - where `path` is stored on disk (folder layout under Constants.Paths,
//   whether it goes through AssetStore or its own dedicated store) and
//   what happens to that file when a bookmark row is deleted
// - the reader context-menu entry point itself ("Bookmark Panel") and the
//   write path that captures the current page's image
// - the dedicated bookmarks view/list this feature is meant to feed -
//   nothing in the schema assumes a particular screen owns this data yet,
//   same open-endedness ActivityHistory.md already notes for HistoryScreen
// - whether a bookmark needs an optional user note field (raised, not
//   decided)
// - whether best-effort reconnection via (seriesId, chapterNumber) should
//   also attempt matching a re-added series by some other stable identity
//   (e.g. origin slug) once the original seriesId is confirmed gone - not
//   scoped for v1 of this feature

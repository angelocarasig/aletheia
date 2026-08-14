//
//  Preferences.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// app-wide user preferences: every UserDefaults key and its default value is
// declared once here, so call sites never carry bare strings or duplicated
// fallbacks. reader-scoped preferences live in ReaderSettings, which follows
// the same idea behind typed accessors and a reader.* namespace
// three states, not two. unset is not "blurred" - it is "no opinion yet", and the
// right answer differs by where you are: opening an adult-only source is itself
// the request to see it, while a mixed search has no such signal and covers by
// default. an explicit choice overrides both
enum AdultBlur: String, CaseIterable {
    case unset
    case blurred
    case shown

    func blurs(adultSource: Bool) -> Bool {
        switch self {
        case .blurred: true
        case .shown: false
        case .unset: !adultSource
        }
    }

    // always explicit from here on: once touched, the preference stops deferring
    // to where it is being read
    func toggled(adultSource: Bool) -> AdultBlur {
        blurs(adultSource: adultSource) ? .shown : .blurred
    }
}

enum Preferences {
    enum Key {
        // predates the namespacing convention; renaming the string would
        // silently reset the stored value, so the legacy key stays
        static let gridColumns = "gridColumns"

        // one key per surface rather than one app-wide answer. search is where
        // you go looking, home and library are what you already own, and the
        // room you are in when someone glances over differs by which - a reveal
        // meant for a search session should not still be on tomorrow's library.
        // the search key predates the split; renaming it would silently reset
        // the stored value, so it keeps its string
        static let blurAdultSearch = "content.blurAdult.state"
        static let blurAdultLibrary = "content.blurAdult.library"
        static let blurAdultHome = "content.blurAdult.home"

        static let includeAdultSources = "search.includeAdultSources"

        static let recentSearches = "search.recent"

        static let bypassAdultSources = "sources.bypassAdult"

        static let librarySort = "library.sort"
        static let librarySortAscending = "library.sortAscending"

        // json, not a key per group - the filter gains groups over time and one
        // blob keeps that from becoming a migration each time
        static let libraryFilter = "library.filter"

        // json blob of seriesId -> dismissal date. reading the series again
        // resurrects it, so the value is a date rather than a bare set
        static let homeDismissed = "home.dismissed"

        // the reading-activity chart remembers how you last looked at it -
        // flipping back to a default you did not choose, every visit, is the
        // kind of small rudeness that makes a screen feel like it is not yours
        static let statsMetric = "stats.metric"
        static let statsScope = "stats.scope"

        // what a library refresh is allowed to skip. all default off: the walk
        // shipped checking everything, and a filter that silently turns itself
        // on changes what "refresh" means without being asked
        static let refreshSkipCompleted = "refresh.skipCompleted"
        static let refreshSkipUnread = "refresh.skipUnread"
        static let refreshSkipNotStarted = "refresh.skipNotStarted"

        // whether the library is checked without being asked. not an interval:
        // ios picks the moment for a processing task whatever we submit - idle
        // and charging, usually overnight - so a chosen cadence would be a
        // promise made by the wrong party. the floor we submit behind is
        // Constants.Refresh.automaticInterval. the two stamps are deliberately
        // separate: a manual refresh must not postpone the automatic one, which
        // is how suwayomi keeps its schedule honest
        static let refreshAutomatic = "refresh.automatic"
        static let refreshedDate = "refresh.lastRun"
        static let refreshedAutomaticallyDate = "refresh.lastAutomaticRun"

        // the queue as an ordered array of chapter ids. what a kill destroys is
        // intent - "download these forty" - and a person cannot reconstruct that;
        // page totals and pages-already-done both rebuild for free. it is also
        // what tells the sweep a half-finished directory is work rather than an
        // orphan, since path is only stamped on completion
        static let downloadQueue = "downloads.queue"
    }

    enum Default {
        static let gridColumns = 3

        // presentation only - it never shapes a request. adult results reach a
        // search at all because the reader ticked a filter option marked
        // .adult, and turning this off does not open that gate. all three start
        // unset, which covers everywhere except inside an adultOnly source
        static let blurAdultSearch = AdultBlur.unset
        static let blurAdultLibrary = AdultBlur.unset
        static let blurAdultHome = AdultBlur.unset

        // retrieval, unlike the one above. global search has no filters, so a
        // tick cannot be the gate there - this is the ask, and off means an
        // adultOnly source is not queried at all
        static let includeAdultSources = false

        // the gate above the gate: while false, adultOnly sources do not exist
        // anywhere - not listed, not searched, not counted as hidden. toggled
        // only by the ten-tap microinteraction on the Sources tab
        static let bypassAdultSources = false

        // the library's own order is what you last chose, not what the schema
        // happens to return - newest first is only where it starts
        static let librarySort = LibrarySort.added
        static let librarySortAscending = false

        // chapters, not pages: it is the unit a reader counts in when they talk
        // about what they read, and the one the rest of the app already uses
        static let statsMetric = ReadingMetric.chapters
        static let statsScope = ReadingChart.Scope.week

        static let refreshSkipCompleted = false
        static let refreshSkipUnread = false
        static let refreshSkipNotStarted = false

        // manual only until asked otherwise: turning on unattended network
        // activity for someone who never asked for it is not a default to inherit
        static let refreshAutomatic = false
    }
}

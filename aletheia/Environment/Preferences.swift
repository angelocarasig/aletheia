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

        // a new key rather than the old Bool one: the stored type changed, and a
        // Bool read back as a raw string is a decode failure, not a default
        static let blurAdultContent = "content.blurAdult.state"

        static let includeAdultSources = "search.includeAdultSources"

        static let bypassAdultSources = "sources.bypassAdult"

        static let librarySort = "library.sort"
        static let librarySortAscending = "library.sortAscending"

        // json, not a key per group - the filter gains groups over time and one
        // blob keeps that from becoming a migration each time
        static let libraryFilter = "library.filter"

        // json blob of seriesId -> dismissal date. reading the series again
        // resurrects it, so the value is a date rather than a bare set
        static let homeDismissed = "home.dismissed"

        static let homeStatRange = "home.statRange"

        // what a library refresh is allowed to skip. all default off: the walk
        // shipped checking everything, and a filter that silently turns itself
        // on changes what "refresh" means without being asked
        static let refreshSkipCompleted = "refresh.skipCompleted"
        static let refreshSkipUnread = "refresh.skipUnread"
        static let refreshSkipNotStarted = "refresh.skipNotStarted"

        // hours between automatic runs, 0 meaning never. the two stamps are
        // deliberately separate: a manual refresh must not postpone the
        // automatic one, which is how suwayomi keeps its schedule honest
        static let refreshInterval = "refresh.interval"
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
        // .adult, and turning this off does not open that gate
        static let blurAdultContent = AdultBlur.unset

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

        // the week is what a landing strip is for - a glance at what is happening
        // now, with the longer views a tap away on the same control
        static let homeStatRange = StatRange.week

        static let refreshSkipCompleted = false
        static let refreshSkipUnread = false
        static let refreshSkipNotStarted = false

        // manual only until asked otherwise. the surveyed apps default to an
        // interval, but they also ship the catch-up and the settings that make
        // one honest - turning it on before those exist would promise a
        // schedule the app cannot keep
        static let refreshInterval = 0
    }
}

//
//  Preferences.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// reader-scoped preferences live in ReaderSettings, which follows the same
// idea behind typed accessors and a reader.* namespace
enum Preferences {
    enum Key {
        // predates the namespacing convention; renaming the string would
        // silently reset the stored value, so the legacy key stays
        static let gridColumns = "gridColumns"

        static let recentSearches = "search.recent"

        static let bypassAdultSources = "sources.bypassAdult"

        static let librarySort = "library.sort"
        static let librarySortAscending = "library.sortAscending"

        // json, not a key per group - the filter gains groups over time and one
        // blob keeps that from becoming a migration each time
        static let libraryFilter = "library.filter"

        // json blob of seriesId -> dismissal date, not a bare set - reading
        // the series again resurrects it
        static let homeDismissed = "home.dismissed"

        static let statsMetric = "stats.metric"
        static let statsScope = "stats.scope"

        // all default off - a filter that silently turns itself on changes
        // what "refresh" means without being asked
        static let refreshSkipCompleted = "refresh.skipCompleted"
        static let refreshSkipUnread = "refresh.skipUnread"
        static let refreshSkipNotStarted = "refresh.skipNotStarted"
        static let refreshSkipRecentInterval = "refresh.skipRecentInterval"

        // not an interval - ios picks the moment for a processing task
        // regardless (idle and charging, usually overnight). the floor we
        // submit behind is Constants.Refresh.automaticInterval. the two
        // stamps are deliberately separate: a manual refresh must not
        // postpone the automatic one
        static let refreshAutomatic = "refresh.automatic"
        static let refreshedDate = "refresh.lastRun"
        static let refreshedAutomaticallyDate = "refresh.lastAutomaticRun"

        // unlike refreshAutomatic this IS an interval - metadata has no
        // BGProcessingTask cadence promise to keep, so a real weekly/monthly
        // choice costs nothing new
        static let metadataRefreshInterval = "metadata.refreshInterval"
        static let metadataRefreshedDate = "metadata.lastRun"

        // own keys, not shared with refreshSkip* - a series skipped by one
        // walk is not necessarily skipped by the other
        static let metadataSkipCompleted = "metadata.skipCompleted"
        static let metadataSkipUnread = "metadata.skipUnread"
        static let metadataSkipNotStarted = "metadata.skipNotStarted"

        // ordered array of chapter ids - what a kill destroys is intent
        // ("download these forty"), which page totals can't reconstruct.
        // also what tells the sweep a half-finished directory is work
        // rather than an orphan, since path is only stamped on completion
        static let downloadQueue = "downloads.queue"

        // stamped by BackupExportScreen once a backup is handed to the file
        // exporter, not when the reader merely opens the screen
        static let libraryBackupExportedDate = "backup.lastExport"

        // absent means "no choice made yet" - RecommendationsService starts
        // with no active model rather than guessing one, so a fresh install
        // never shows a pack as active before it's actually downloaded
        static let recommenderPackId = "recommender.packId"
    }

    enum Default {
        static let gridColumns = 3

        // while false, adultOnly sources do not exist anywhere - not listed,
        // not searched, not counted as hidden. toggled only by the ten-tap
        // microinteraction on the Sources tab
        static let bypassAdultSources = false

        static let librarySort = LibrarySort.added
        static let librarySortAscending = false

        static let statsMetric = ReadingMetric.chapters
        static let statsScope = ReadingChart.Scope.week

        static let refreshSkipCompleted = false
        static let refreshSkipUnread = false
        static let refreshSkipNotStarted = false
        static let refreshSkipRecentInterval = SkipRecentInterval.off

        // manual only until asked otherwise - unattended network activity is
        // not a default to inherit
        static let refreshAutomatic = false

        static let metadataRefreshInterval = MetadataRefreshInterval.off

        static let metadataSkipCompleted = false
        static let metadataSkipUnread = false
        static let metadataSkipNotStarted = false
    }
}

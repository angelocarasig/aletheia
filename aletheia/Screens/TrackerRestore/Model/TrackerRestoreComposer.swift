//
//  TrackerRestoreComposer.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation
import GRDB
import Observation
import SwiftUI

// owns the whole restore flow's state - which tracker, which sources, the
// rows pulled from it, and every action the two screens drive. one composer
// rather than one per screen because the setup step's answers (tracker,
// sources) are exactly what the queue step needs, and passing them through
// init rather than a shared composer would mean re-deriving them
@MainActor
@Observable
final class TrackerRestoreComposer {
    private let importSources: [Tracker: TrackerImportSource]
    private let searching: TrackerRestoreSearching
    private let committing: TrackerRestoreCommitting
    private let registry: Compositor.Registry
    private let database: DatabaseClient
    private let log: AppLog

    private(set) var availableSources: [Source]
    var selectedSourceSlugs: Set<String>

    // which of the offered trackers Start pulls from - a plain var rather
    // than a picker sheet's own state, since the whole session is one pull
    // from one tracker
    var selectedTracker: Tracker

    private(set) var loading = false
    private(set) var rows: [TrackerRestoreRow] = []
    private(set) var loadFailure: String?

    var page = 0
    var filter = RowFilter.remaining {
        didSet { guard filter != oldValue else { return }; page = 0 }
    }

    private enum Layout {
        static let pageSize = 20
    }

    // pills over the working set, not a fourth "all" - a saved or skipped row
    // has nothing left to do, so there is no view that needs to show every
    // row at once
    enum RowFilter: String, CaseIterable, Identifiable, Equatable {
        case remaining
        case linked
        case saved
        case failed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .remaining: "Remaining"
            case .linked: "Already Linked"
            case .saved: "Saved"
            case .failed: "Failed"
            }
        }
    }

    init(
        importSources: [TrackerImportSource],
        searching: TrackerRestoreSearching,
        committing: TrackerRestoreCommitting,
        registry: Compositor.Registry,
        database: DatabaseClient,
        log: AppLog = .shared
    ) {
        self.importSources = Dictionary(uniqueKeysWithValues: importSources.map { ($0.tracker, $0) })
        self.selectedTracker = importSources.first?.tracker ?? .anilist
        self.searching = searching
        self.committing = committing
        self.registry = registry
        self.database = database
        self.log = log

        // the same existence gate SearchViewModel's own source list uses -
        // while bypassAdultSources is off, an adultOnly source does not
        // exist here at all, not merely hidden
        let defaults = UserDefaults.standard
        let unlocked = defaults.bool(forKey: Preferences.Key.bypassAdultSources)
            && defaults.bool(forKey: Preferences.Key.includeAdultSources)
        self.availableSources = unlocked ? registry.sources : registry.sources.filter { !$0.descriptor.adultOnly }

        // nothing pre-checked - restoring a whole library is a real decision
        // about where its chapters come from, not a default to accept
        self.selectedSourceSlugs = []
    }

    private var selectedSources: [Source] {
        availableSources.filter { selectedSourceSlugs.contains($0.descriptor.slug) }
    }

    // resolved once per composer rather than per row - a candidate carries
    // only its source's slug, and the queue's row view needs the source
    // itself to draw its icon
    var sourcesBySlug: [String: Source] {
        Dictionary(uniqueKeysWithValues: availableSources.map { ($0.descriptor.slug, $0) })
    }

    // paginated over the current pill's rows, not the master list - a row
    // that just saved leaves this set on its own, which is what gives the
    // reader "a fresh 20" after clearing a page rather than a fixed window
    // that still shows what it already finished with
    private var filteredRows: [TrackerRestoreRow] {
        switch filter {
        case .remaining: rows.filter { !$0.alreadyLinked && !$0.isSettled }
        case .linked: rows.filter { $0.alreadyLinked }
        case .saved: rows.filter { $0.outcome == .saved }
        case .failed: rows.filter { if case .skipped = $0.outcome { true } else { false } }
        }
    }

    var pageCount: Int {
        filteredRows.isEmpty ? 0 : (filteredRows.count + Layout.pageSize - 1) / Layout.pageSize
    }

    var currentPageRows: [TrackerRestoreRow] {
        let start = page * Layout.pageSize
        guard start < filteredRows.count else { return [] }
        return Array(filteredRows[start..<min(start + Layout.pageSize, filteredRows.count)])
    }

    func count(for filter: RowFilter) -> Int {
        switch filter {
        case .remaining: rows.count { !$0.alreadyLinked && !$0.isSettled }
        case .linked: rows.count { $0.alreadyLinked }
        case .saved: savedCount
        case .failed: rows.count { if case .skipped = $0.outcome { true } else { false } }
        }
    }

    var savedCount: Int { rows.count { $0.outcome == .saved } }
    var skippedCount: Int { count(for: .failed) }

    // MARK: Setup

    func toggleSource(_ slug: String) {
        if selectedSourceSlugs.contains(slug) {
            selectedSourceSlugs.remove(slug)
        } else {
            selectedSourceSlugs.insert(slug)
        }
    }

    func start() async {
        guard !loading, let importSource = importSources[selectedTracker] else { return }
        loading = true
        defer { loading = false }

        do {
            let entries = try await importSource.fetchLibrary()
            let linked = try await alreadyLinkedRemoteIds(among: entries.map(\.id))
            rows = entries.map { TrackerRestoreRow(entry: $0, alreadyLinked: linked.contains($0.id)) }
            loadFailure = nil
        } catch {
            loadFailure = Failure(error, fallback: "Couldn't load your list").sentence
            log.log("restore fetchLibrary failed - \(error)", level: .error, category: "restore")
        }
    }

    // a preventive check ahead of any search: a tracker's own list can carry
    // an entry the reader already linked before this pull ran - by a
    // previous restore, or by hand from Details - and creating a series for
    // it a second time is exactly the origin-uniqueness crash this flow used
    // to hit. those rows are marked rather than dropped, so they stay visible
    // in their own pill instead of just vanishing from the count
    private func alreadyLinkedRemoteIds(among remoteIds: [Int64]) async throws -> Set<Int64> {
        guard !remoteIds.isEmpty else { return [] }

        let tracker = selectedTracker
        let rows = try await database.reader.read { db in
            try SeriesTrackerRecord
                .filter(SeriesTrackerRecord.Columns.tracker == tracker.rawValue)
                .filter(remoteIds.contains(SeriesTrackerRecord.Columns.remoteId))
                .fetchAll(db)
        }
        return Set(rows.map(\.remoteId))
    }

    // MARK: Queue

    // sequential per row, matching StashApp's Tagger - each search() call
    // already fans out concurrently across the selected sources internally,
    // so this is the only serialization needed, not a second layer of it
    func searchAllOnCurrentPage() async {
        let ids = currentPageRows.filter { $0.match == .idle }.map(\.id)
        for id in ids {
            await search(id)
        }
    }

    // query defaults to the tracker's own title - the picker sheet is what
    // lets a reader override it when the tracker's title is not what any
    // installed source calls the series
    func search(_ id: Int64, query: String? = nil) async {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let title = query ?? rows[index].entry.title
        rows[index].match = .searching
        // a fresh search is a fresh attempt - a stale failure from the last
        // candidate should not carry over to whatever this one finds
        rows[index].outcome = nil

        let match = await searching.search(title: title, in: selectedSources)

        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].match = match
    }

    func select(_ candidate: TrackerRestoreCandidate, for id: Int64) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].match = .found(rows[index].match.candidates, selected: candidate)
        // picking a (possibly different) candidate is also a fresh attempt
        rows[index].outcome = nil
    }

    func save(_ id: Int64) async {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              let candidate = rows[index].match.selected
        else { return }

        withAnimation(.settle) { rows[index].saving = true }
        let outcome = await committing.commit(rows[index].entry, candidate: candidate, tracker: selectedTracker)

        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        // this is the mutation that can drop the row out of whatever pill is
        // currently showing (Remaining, once outcome lands) - animated here
        // rather than left to whatever transaction happens to be active when
        // the awaited commit returns, which is generally none at all
        withAnimation(.settle) {
            rows[index].saving = false
            rows[index].outcome = outcome
        }
    }

    // the reader's own call that a row is done being retried - moves it out
    // of Remaining and into the Failed pill, carrying whatever reason it
    // last gave (a save failure, "Stopped" for a cancelled attempt, or the
    // search's own dead end) so it is never silently lost
    func skip(_ id: Int64) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }

        // this is what moves the row out of Remaining and into Failed, so it
        // gets the same animated-mutation treatment save() does
        withAnimation(.settle) {
            switch rows[index].outcome {
            case .failed(let reason): rows[index].outcome = .skipped(reason)
            case .cancelled: rows[index].outcome = .skipped("Stopped")
            case .saved, .skipped: break
            case nil:
                switch rows[index].match {
                case .notFound: rows[index].outcome = .skipped("No match found.")
                case .failed(let reason): rows[index].outcome = .skipped(reason)
                case .idle, .searching, .found: break
                }
            }
        }
    }
}

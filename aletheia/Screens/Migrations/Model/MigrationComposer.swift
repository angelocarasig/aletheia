//
//  MigrationComposer.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import Observation
import SwiftUI

// file-scope rather than nested - a static stored property is not allowed
// inside a type nested in a generic type
private enum MigrationComposerLayout {
    static let pageSize = 20
}

// owns one migration session's whole state - the rows pulled from its
// source, which sources they search against, and every action the queue
// screen drives. generic over the entry type, so tracker restore, source
// migration and disconnected-source migration all run the same queue,
// pagination, search and save/skip machinery through their own source and
// committer rather than three copies of it.
//
// takes exactly one already-resolved MigrationSource - unlike the tracker
// restore composer this replaces, there is no live re-selection of "which
// source pulls the entries" inside the composer itself. a flow that offers
// that choice (tracker restore's own tracker picker) makes it on its own
// setup screen, as plain local state, and only resolves the concrete source
// once Start is tapped
@MainActor
@Observable
final class MigrationComposer<Entry: MigrationEntry> {
    private let source: any MigrationSource<Entry>
    private let searching: any MigrationSearching
    private let committing: any MigrationCommitting<Entry>
    // an entry the precheck already resolved locally, before any search runs
    // - the same guard tracker restore uses against "this remoteId is
    // already linked", generalized to whatever a given flow needs to check.
    // defaults to finding nothing, since not every flow needs one
    private let precheck: ([Entry]) async -> Set<Entry.ID>
    private let log: AppLog

    private(set) var availableSources: [Source]
    var selectedSourceSlugs: Set<String>

    private(set) var loading = false
    private(set) var rows: [MigrationRow<Entry>] = []
    private(set) var loadFailure: String?

    var page = 0
    var filter = RowFilter.remaining {
        didSet { guard filter != oldValue else { return }; page = 0 }
    }

    // the pill label for a precheck-matched row - "Already Linked" reads
    // right for tracker restore, a different flow names its own precheck
    private let precheckLabel: String

    // pills over the working set, not a fourth "all" - a saved or skipped row
    // has nothing left to do, so there is no view that needs to show every
    // row at once
    enum RowFilter: CaseIterable, Identifiable, Hashable {
        case remaining
        case precheckMatched
        case saved
        case failed

        var id: Self { self }
    }

    init(
        source: any MigrationSource<Entry>,
        searching: any MigrationSearching,
        committing: any MigrationCommitting<Entry>,
        registry: Compositor.Registry,
        precheck: @escaping ([Entry]) async -> Set<Entry.ID> = { _ in [] },
        precheckLabel: String = "Already Linked",
        log: AppLog = .shared
    ) {
        self.source = source
        self.searching = searching
        self.committing = committing
        self.precheck = precheck
        self.precheckLabel = precheckLabel
        self.log = log

        // the same existence gate SearchViewModel's own source list uses -
        // while bypassAdultSources is off, an adultOnly source does not
        // exist here at all, not merely hidden
        let defaults = UserDefaults.standard
        let unlocked = defaults.bool(forKey: Preferences.Key.bypassAdultSources)
            && defaults.bool(forKey: Preferences.Key.includeAdultSources)
        self.availableSources = unlocked ? registry.sources : registry.sources.filter { !$0.descriptor.adultOnly }

        // nothing pre-checked - migrating a whole library is a real decision
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

    func label(for filter: RowFilter) -> String {
        switch filter {
        case .remaining: "Remaining"
        case .precheckMatched: precheckLabel
        case .saved: "Saved"
        case .failed: "Failed"
        }
    }

    // paginated over the current pill's rows, not the master list - a row
    // that just saved leaves this set on its own, which is what gives the
    // reader "a fresh 20" after clearing a page rather than a fixed window
    // that still shows what it already finished with
    private var filteredRows: [MigrationRow<Entry>] {
        switch filter {
        case .remaining: rows.filter { !$0.precheckMatched && !$0.isSettled }
        case .precheckMatched: rows.filter { $0.precheckMatched }
        case .saved: rows.filter { $0.outcome == .saved }
        case .failed: rows.filter { if case .skipped = $0.outcome { true } else { false } }
        }
    }

    var pageCount: Int {
        filteredRows.isEmpty ? 0 : (filteredRows.count + MigrationComposerLayout.pageSize - 1) / MigrationComposerLayout.pageSize
    }

    var currentPageRows: [MigrationRow<Entry>] {
        let start = page * MigrationComposerLayout.pageSize
        guard start < filteredRows.count else { return [] }
        return Array(filteredRows[start..<min(start + MigrationComposerLayout.pageSize, filteredRows.count)])
    }

    func count(for filter: RowFilter) -> Int {
        switch filter {
        case .remaining: rows.count { !$0.precheckMatched && !$0.isSettled }
        case .precheckMatched: rows.count { $0.precheckMatched }
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
        guard !loading else { return }
        loading = true
        defer { loading = false }

        do {
            let entries = try await source.fetch()
            let matched = await precheck(entries)
            rows = entries.map { MigrationRow(entry: $0, precheckMatched: matched.contains($0.id)) }
            loadFailure = nil
        } catch {
            loadFailure = Failure(error, fallback: "Couldn't load the list").sentence
            log.log("migration fetch failed - \(error)", level: .error, category: "migration")
        }
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

    // query defaults to the entry's own title - the picker sheet is what
    // lets a reader override it when the entry's title is not what any
    // installed source calls the series
    func search(_ id: Entry.ID, query: String? = nil) async {
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

    func select(_ candidate: MigrationCandidate, for id: Entry.ID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].match = .found(rows[index].match.candidates, selected: candidate)
        // picking a (possibly different) candidate is also a fresh attempt
        rows[index].outcome = nil
    }

    func save(_ id: Entry.ID) async {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              let candidate = rows[index].match.selected
        else { return }

        withAnimation(.settle) { rows[index].saving = true }
        let outcome = await committing.commit(rows[index].entry, candidate: candidate)

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
    func skip(_ id: Entry.ID) {
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

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

@MainActor
@Observable
final class MigrationComposer<Entry: MigrationEntry> {
    private let source: any MigrationSource<Entry>
    private let searching: any MigrationSearching
    private let committing: any MigrationCommitting<Entry>
    private let precheck: ([Entry]) async -> Set<Entry.ID>
    private let initialMatch: (Entry) -> MigrationMatch
    private let log: AppLog

    private(set) var availableSources: [Source]
    var selectedSourceSlugs: Set<String>

    private(set) var loading = false
    private(set) var rows: [MigrationRow<Entry>] = []
    private(set) var loadFailure: String?

    var page = 0
    var filter = RowFilter.remaining {
        didSet {
            guard filter != oldValue else { return }
            page = 0
        }
    }

    private let precheckLabel: String

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
        initialMatch: @escaping (Entry) -> MigrationMatch = { _ in .idle },
        log: AppLog = .shared
    ) {
        self.source = source
        self.searching = searching
        self.committing = committing
        self.precheck = precheck
        self.initialMatch = initialMatch
        self.precheckLabel = precheckLabel
        self.log = log

        let unlocked = UserDefaults.standard.bool(forKey: Preferences.Key.bypassAdultSources)
        self.availableSources =
            unlocked ? registry.sources : registry.sources.filter { !$0.descriptor.adultOnly }

        self.selectedSourceSlugs = []
    }

    private var selectedSources: [Source] {
        availableSources.filter { selectedSourceSlugs.contains($0.descriptor.slug) }
    }

    // a candidate carries only its source's slug; the queue's row view needs
    // the source itself to draw its icon
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

    private var filteredRows: [MigrationRow<Entry>] {
        switch filter {
        case .remaining: rows.filter { !$0.precheckMatched && !$0.isSettled }
        case .precheckMatched: rows.filter { $0.precheckMatched }
        case .saved: rows.filter { $0.outcome == .saved }
        case .failed: rows.filter { if case .skipped = $0.outcome { true } else { false } }
        }
    }

    var pageCount: Int {
        filteredRows.isEmpty
            ? 0
            : (filteredRows.count + MigrationComposerLayout.pageSize - 1)
                / MigrationComposerLayout.pageSize
    }

    var currentPageRows: [MigrationRow<Entry>] {
        let start = page * MigrationComposerLayout.pageSize
        guard start < filteredRows.count else { return [] }
        return Array(
            filteredRows[start..<min(start + MigrationComposerLayout.pageSize, filteredRows.count)])
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
            rows = entries.map {
                MigrationRow(
                    entry: $0, precheckMatched: matched.contains($0.id), match: initialMatch($0))
            }
            loadFailure = nil
        } catch {
            loadFailure = Failure(error, fallback: "Couldn't load the list").sentence
            log.log("migration fetch failed - \(error)", level: .error, category: "migration")
        }
    }

    // MARK: Queue

    // sequential per row - search() already fans out across selected sources
    // internally, so parallelizing here would double up the concurrency
    func searchAllOnCurrentPage() async {
        let ids = currentPageRows.filter { $0.match == .idle }.map(\.id)
        for id in ids {
            await search(id)
        }
    }

    func search(_ id: Entry.ID, query: String? = nil) async {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let title = query ?? rows[index].entry.title
        rows[index].match = .searching
        rows[index].outcome = nil

        let match = await searching.search(title: title, in: selectedSources)

        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].match = match
    }

    func select(_ candidate: MigrationCandidate, for id: Entry.ID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].match = .found(rows[index].match.candidates, selected: candidate)
        rows[index].outcome = nil
    }

    func save(_ id: Entry.ID) async {
        guard let index = rows.firstIndex(where: { $0.id == id }),
            let candidate = rows[index].match.selected
        else { return }

        withAnimation(.settle) { rows[index].saving = true }
        let outcome = await committing.commit(rows[index].entry, candidate: candidate)

        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        // animated explicitly - after an await there is no active transaction
        // to inherit, so this would otherwise land unanimated
        withAnimation(.settle) {
            rows[index].saving = false
            rows[index].outcome = outcome
        }
    }

    func skip(_ id: Entry.ID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }

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

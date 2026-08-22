//
//  SearchViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class SearchViewModel {
    static let limit = 10

    enum SectionPhase: String, Equatable {
        case searching
        case loaded
        case failed
    }

    struct Section: Identifiable {
        let source: Source
        var phase: SectionPhase = .searching
        var stubs: [SeriesStub] = []
        var hasMore = false

        var id: String { source.descriptor.slug }
        var name: String { source.descriptor.name }
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    // MARK: Adult sources

    // while false, adultOnly sources don't just get excluded - they don't exist
    var bypassAdult = Preferences.Default.bypassAdultSources {
        didSet {
            guard bypassAdult != oldValue else { return }
            scheduleSearch()
        }
    }

    // never filtered out of `sources` itself - correlators are built per source
    // at configure, and an excluded one simply never observes
    private var searchable: [Source] {
        let base = bypassAdult ? sources : sources.filter { !$0.descriptor.adultOnly }
        return base.filter { !hiddenSlugs.contains($0.descriptor.slug) }
    }

    // kept live by visibilityTask, not a one-time read at configure - see
    // observeHiddenSlugs
    @ObservationIgnored private var hiddenSlugs: Set<String> = []

    // adult-only sources specifically, not every hidden source - a non-adult
    // source hidden by choice doesn't belong in an "adult sources hidden" count
    var hiddenAdultCount: Int {
        guard bypassAdult else { return 0 }
        return sources.count {
            $0.descriptor.adultOnly && hiddenSlugs.contains($0.descriptor.slug)
        }
    }
    private(set) var active = false
    private(set) var submitted = ""
    private(set) var sections: [Section] = []

    @ObservationIgnored private var sources: [Source] = []
    @ObservationIgnored private var correlators: [String: Correlator] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var visibilityTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private enum Timing {
        static let debounce: Duration = .milliseconds(400)
    }

    var allEmpty: Bool {
        !sections.isEmpty && sections.allSatisfy { $0.phase == .loaded && $0.stubs.isEmpty }
    }

    var stateKey: String {
        (active ? "active" : "idle")
            + sections.map { "|\($0.id):\($0.phase.rawValue):\($0.stubs.count)" }.joined()
    }

    // correlators must observe the same client the app writes through - a second
    // pool on the same file never sees those transactions, so badges would freeze
    func configure(sources: [Source], database: DatabaseClient) {
        guard self.sources.isEmpty else { return }
        self.sources = sources
        self.correlators = Dictionary(
            uniqueKeysWithValues: sources.map {
                ($0.descriptor.slug, Correlator(sourceSlug: $0.descriptor.slug, database: database))
            })

        // live, not lifecycle-timed - a source flipped to "Show" in Settings
        // must reappear the moment the change lands, not wait for this screen
        // to re-appear, since pushing/popping a navigationDestination on the
        // same stack never re-fires onAppear on the view underneath it
        visibilityTask = Task { [weak self] in
            guard let self else { return }
            for await hidden in self.observeHiddenSlugs(sources: sources, database: database) {
                guard !Task.isCancelled else { return }
                guard hidden != self.hiddenSlugs else { continue }
                self.hiddenSlugs = hidden
                guard self.active else { continue }
                self.run(self.submitted)
            }
        }
    }

    private func observeHiddenSlugs(sources: [Source], database: DatabaseClient)
        -> AsyncStream<Set<String>>
    {
        let bySlug = Dictionary(uniqueKeysWithValues: sources.map { ($0.descriptor.slug, $0) })
        let reader = database.reader

        return AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SourceRecord.fetchAll(db).compactMap { record -> String? in
                    guard let source = bySlug[record.slug] else { return nil }
                    let adult = source.descriptor.adultOnly
                    return record.hideFromSearch.hides(adultSource: adult) ? record.slug : nil
                }
            }

            let cancellable = observation.start(
                in: reader,
                onError: { _ in continuation.finish() },
                onChange: { continuation.yield(Set($0)) }
            )

            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func match(in sectionID: String, for stub: SeriesStub) -> SeriesMatch? {
        correlators[sectionID]?[stub]
    }

    func retry(_ sectionID: String) {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }),
            sections[index].phase == .failed
        else { return }

        sections[index].phase = .searching
        let source = sections[index].source
        let text = submitted
        let expected = generation
        Task { [weak self] in
            await self?.searchSection(
                index: index, source: source, text: text, generation: expected)
        }
    }

    // visibilityTask deliberately outlives stop()/resume() - it must keep
    // observing while a pushed screen (like source settings) sits on top,
    // which is exactly when a hideFromSearch change happens
    func stop() {
        task?.cancel()
        correlators.values.forEach { $0.stop() }
    }

    func resume() {
        for section in sections where section.phase == .loaded {
            correlators[section.id]?.observe(section.stubs)
        }
    }

    // also the toggle's path back in, which is why it re-reads `query` rather
    // than taking the text as a parameter
    private func scheduleSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            task?.cancel()
            generation += 1
            submitted = ""
            active = false
            sections = []
            correlators.values.forEach { $0.stop() }
        } else {
            run(trimmed)
        }
    }

    private func run(_ trimmed: String) {
        task?.cancel()
        generation += 1
        let expected = generation

        task = Task { [weak self] in
            try? await Task.sleep(for: Timing.debounce)
            guard let self, !Task.isCancelled, self.generation == expected else { return }
            guard !self.sources.isEmpty else { return }

            // captured once - sections[index] below is positional against this
            // array, so re-reading the computed property between the two uses
            // could file one source's results under another's heading
            let searching = self.searchable

            self.submitted = trimmed
            RecentSearches.record(trimmed)
            self.active = true
            self.sections = searching.map { Section(source: $0) }

            await withTaskGroup(of: Void.self) { group in
                for (index, source) in searching.enumerated() {
                    group.addTask { @MainActor [weak self] in
                        await self?.searchSection(
                            index: index,
                            source: source,
                            text: trimmed,
                            generation: expected
                        )
                    }
                }
            }
        }
    }

    private func searchSection(index: Int, source: Source, text: String, generation expected: Int)
        async
    {
        let query = SearchQuery(text: text, filters: [], sort: nil, page: 1)
        do {
            let page = try await source.search(query)
            guard generation == expected, sections.indices.contains(index) else { return }

            let stubs = Array(page.items.prefix(Self.limit))
            sections[index].stubs = stubs
            sections[index].hasMore = page.next != nil || page.items.count > Self.limit
            sections[index].phase = .loaded
            correlators[source.descriptor.slug]?.observe(stubs)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard generation == expected, sections.indices.contains(index) else { return }
            sections[index].phase = .failed
            AppLog.shared.log(
                "global search failed for '\(source.descriptor.slug)' - \(error)", level: .error,
                category: "search")
        }
    }
}

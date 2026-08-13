//
//  SearchViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation
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

    // mirrors the stored preference, written by the view that owns the @AppStorage.
    // this screen has no filters, so a tick cannot be the gate here - the toggle
    // IS the ask, and changing it re-runs the search the way a keystroke does
    var includeAdult = Preferences.Default.includeAdultSources {
        didSet {
            guard includeAdult != oldValue else { return }
            scheduleSearch()
        }
    }

    // while false, adultOnly sources are not merely excluded - they do not
    // exist, so nothing counts them or hints at them
    var bypassAdult = Preferences.Default.bypassAdultSources {
        didSet {
            guard bypassAdult != oldValue else { return }
            scheduleSearch()
        }
    }

    // never filtered out of `sources` itself - correlators are built per source at
    // configure and an excluded one simply never observes
    private var searchable: [Source] {
        bypassAdult && includeAdult ? sources : sources.filter { !$0.descriptor.adultOnly }
    }

    var hiddenAdultCount: Int {
        bypassAdult && !includeAdult ? sources.count { $0.descriptor.adultOnly } : 0
    }
    private(set) var active = false
    private(set) var submitted = ""
    private(set) var sections: [Section] = []

    @ObservationIgnored private var sources: [Source] = []
    @ObservationIgnored private var correlators: [String: Correlator] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private enum Timing {
        static let debounce: Duration = .milliseconds(400)
    }

    var allEmpty: Bool {
        !sections.isEmpty && sections.allSatisfy { $0.phase == .loaded && $0.stubs.isEmpty }
    }

    // one equatable value covering every state the results area renders from,
    // so a single .animation(value:) can drive all section transitions
    var stateKey: String {
        (active ? "active" : "idle")
            + sections.map { "|\($0.id):\($0.phase.rawValue):\($0.stubs.count)" }.joined()
    }

    // correlators must observe the same client the app writes through - a second
    // pool on the same file never sees those transactions, so badges would freeze
    func configure(sources: [Source], database: DatabaseClient) {
        guard self.sources.isEmpty else { return }
        self.sources = sources
        self.correlators = Dictionary(uniqueKeysWithValues: sources.map {
            ($0.descriptor.slug, Correlator(sourceSlug: $0.descriptor.slug, database: database))
        })
    }

    func match(in sectionID: String, for stub: SeriesStub) -> SeriesMatch? {
        correlators[sectionID]?[stub]
    }

    func retry(_ sectionID: String) {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }),
              sections[index].phase == .failed else { return }

        sections[index].phase = .searching
        let source = sections[index].source
        let text = submitted
        let expected = generation
        Task { [weak self] in
            await self?.searchSection(index: index, source: source, text: text, generation: expected)
        }
    }

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

            // captured once. `sections` is positional - searchSection writes into
            // sections[index], and the index comes from this array - so re-reading
            // the computed property would let a toggle flipped between the two
            // uses file one source's results under another's heading
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

    // a stale task must never write into a newer run's sections, so every write
    // is gated on the generation it was spawned for
    private func searchSection(index: Int, source: Source, text: String, generation expected: Int) async {
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
            AppLog.shared.log("global search failed for '\(source.descriptor.slug)' - \(error)", level: .error, category: "search")
        }
    }
}

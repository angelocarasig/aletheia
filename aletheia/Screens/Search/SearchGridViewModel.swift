//
//  SearchGridViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Observation
import Foundation

struct GridEntry: Identifiable, Sendable {
    let stub: SeriesStub
    let page: Int

    var id: String { "\(stub.slug)#\(page)" }
}

@MainActor
@Observable
final class SearchGridViewModel {
    private let source: Source
    private let preset: SourcePreset?
    private let correlator: Correlator

    private(set) var entries: [GridEntry] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    var errorMessage: String?

    var searchText: String
    var filters: [FilterSelection]
    var sort: SortSelection?

    private var page = 1
    private let debounce: Duration = .milliseconds(300)

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    var title: String { preset?.name ?? "Search" }
    var sourceName: String { source.descriptor.name }
    var referer: URL { source.descriptor.referer }

    var supportedFilters: [SourceFilter] { source.descriptor.supportedFilters }
    var supportedSorts: [SourceFilter.Sort] { source.descriptor.supportedSorts }
    var sortOptions: [SourceFilter.Option] { supportedSorts.first?.options ?? [] }
    var supportsRefine: Bool { !supportedFilters.isEmpty }

    var selectedSortID: String? { sort?.optionID }

    var selectedSortName: String {
        let id = sort?.optionID ?? supportedSorts.first.flatMap {
            $0.options.indices.contains($0.defaultIndex) ? $0.options[$0.defaultIndex].id : $0.options.first?.id
        }
        return sortOptions.first { $0.id == id }?.name ?? "Sort"
    }

    var activeFilterCount: Int {
        filters.reduce(0) { total, selection in
            switch selection {
            case let .text(_, value): return total + (value.isEmpty ? 0 : 1)
            case .number: return total + 1
            case .select: return total
            case let .multiSelect(_, included, excluded): return total + included.count + excluded.count
            }
        }
    }

    func selectSort(_ optionID: String) {
        sort = SortSelection(optionID: optionID, ascending: false)
    }

    func selection(for id: String) -> FilterSelection? {
        filters.first { $0.id == id }
    }

    func setSelection(_ selection: FilterSelection?, for id: String) {
        filters.removeAll { $0.id == id }
        if let selection { filters.append(selection) }
    }

    func clearFilters() {
        filters.removeAll()
    }

    init(source: Source, preset: SourcePreset, database: DatabaseClient = .client) {
        self.source = source
        self.preset = preset
        self.correlator = Correlator(sourceSlug: source.descriptor.slug, database: database)
        self.searchText = ""
        self.filters = preset.filters
        self.sort = preset.sort
    }

    init(source: Source, query: String, database: DatabaseClient = .client) {
        self.source = source
        self.preset = nil
        self.correlator = Correlator(sourceSlug: source.descriptor.slug, database: database)
        self.searchText = query
        self.filters = []
        self.sort = nil
    }

    init(source: Source, database: DatabaseClient = .client) {
        self.source = source
        self.preset = nil
        self.correlator = Correlator(sourceSlug: source.descriptor.slug, database: database)
        self.searchText = ""
        self.filters = []
        self.sort = nil
    }

    func match(for stub: SeriesStub) -> SeriesMatch? {
        correlator[stub]
    }

    func startObserving() {
        observationTask?.cancel()
        // restore the badge observation after a stop, without refetching
        correlator.observe(entries.map(\.stub))
        observationTask = Task { @MainActor in
            var previous = state
            if entries.isEmpty { triggerSearch() }

            while !Task.isCancelled {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { break }

                let current = state
                if current != previous {
                    previous = current
                    resetPagination()
                    triggerSearch()
                }
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        searchTask?.cancel()
        observationTask = nil
        searchTask = nil
        correlator.stop()
    }

    func loadMore() {
        guard !isLoading, !isLoadingMore, hasMore, errorMessage == nil else { return }
        page += 1
        triggerSearch(loadingMore: true)
    }

    func retry() {
        resetPagination()
        triggerSearch()
    }

    private var state: SearchState {
        SearchState(text: searchText, filters: filters, sort: sort)
    }

    private func triggerSearch(loadingMore: Bool = false) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            await performSearch(loadingMore: loadingMore)
        }
    }

    private func performSearch(loadingMore: Bool) async {
        if loadingMore { isLoadingMore = true } else { isLoading = true }

        do {
            try Task.checkCancellation()

            let query = SearchQuery(
                text: searchText.isEmpty ? nil : searchText,
                filters: filters,
                sort: sort,
                page: page
            )
            let result = try await source.search(query)

            try Task.checkCancellation()

            let fetched = result.items.map { GridEntry(stub: $0, page: page) }
            if loadingMore {
                entries.append(contentsOf: fetched)
            } else {
                entries = fetched
            }
            hasMore = result.next != nil
            errorMessage = nil
            correlator.observe(entries.map(\.stub))
        } catch is CancellationError {
            if loadingMore, page > 1 { page -= 1 }
        } catch let urlError as URLError where urlError.code == .cancelled {
            if loadingMore, page > 1 { page -= 1 }
        } catch {
            if loadingMore, page > 1 { page -= 1 }
            errorMessage = String(describing: error)
            AppLog.shared.log("search failed for '\(source.descriptor.slug)' — \(error)", category: "search")
        }

        if loadingMore { isLoadingMore = false } else { isLoading = false }
    }

    private func resetPagination() {
        page = 1
        entries = []
        hasMore = true
        errorMessage = nil
    }
}

private struct SearchState: Equatable {
    let text: String
    let filters: [FilterSelection]
    let sort: SortSelection?
}

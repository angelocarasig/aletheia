//
//  SearchGridViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import Observation

import struct SwiftUI.ImageResource

struct GridEntry: Identifiable, Equatable, Sendable {
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
    var failure: Failure?

    var searchText: String
    var filters: [FilterSelection]
    var sort: SortSelection?

    private var page = 1
    private let debounce: Duration = .milliseconds(300)

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    var title: String { preset?.name ?? "Search" }
    var isAdultSource: Bool { source.descriptor.adultOnly }
    var sourceName: String { source.descriptor.name }
    var sourceIcon: ImageResource { source.descriptor.icon }
    var sourceDescription: String { source.descriptor.description }
    var referer: URL { source.descriptor.referer }

    // MARK: Adult content

    // stored rather than recomputed per read, since it's only invalidated by
    // filter mutators but read on every header evaluation
    private(set) var gateOpen = false

    var supportedFilters: [SourceFilter] { source.descriptor.supportedFilters }
    var supportedSort: SourceFilter.Sort { source.descriptor.supportedSort }
    var sortOptions: [SourceFilter.Option] { supportedSort.options }
    var supportsRefine: Bool { !supportedFilters.isEmpty && route == nil }

    // dropping this from performSearch once caused a preset with a route to
    // fall back to a plain match-all search, showing different series than
    // the shelf it was pushed from under one title
    var route: String? { preset?.route }

    // switching sort inside a preset would leave a screen titled "Popular"
    // showing something else - the way to a different ordering is a different preset
    var supportsSort: Bool { preset == nil }

    // a shelf ignores text and filters outright (verified: no query param
    // changes its results), so the controls are hidden rather than rendered inert
    var supportsSearch: Bool { route == nil }

    var selectedSortID: String? { sort?.optionID }

    var selectedSortName: String {
        let id = sort?.optionID ?? supportedSort.defaultSort
        return sortOptions.first { $0.id == id }?.name ?? "Sort"
    }

    // what "Automatic" resolves to, named rather than implied
    var defaultSortName: String {
        let id = supportedSort.defaultSort
        guard let name = sortOptions.first(where: { $0.id == id })?.name else { return "Automatic" }
        return "Automatic (\(name))"
    }

    var activeFilterCount: Int {
        filters.reduce(0) { total, selection in
            switch selection {
            case .text(_, let value): return total + (value.isEmpty ? 0 : 1)
            case .number: return total + 1
            // omitting this once left the pill reading "Refine" with no count
            // on a source with select filters
            case .select: return total + 1
            case .multiSelect(_, let included, let excluded):
                return total + included.count + excluded.count
            }
        }
    }

    // a preset searches on open regardless of this; only a bare search screen
    // treats empty input as nothing to show rather than firing a match-all request
    var isIdle: Bool {
        guard preset == nil else { return false }
        return searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filters.isEmpty
            && sort == nil
    }

    // MARK: Applied filters

    struct Applied: Identifiable, Hashable, Sendable {
        let filterID: String
        let optionID: String
        let name: String
        let excluded: Bool

        var id: String { "\(filterID)\u{1F}\(optionID)" }
    }

    var applied: [Applied] {
        filters.flatMap { selection -> [Applied] in
            switch selection {
            case .multiSelect(let id, let included, let excluded):
                return included.map {
                    Applied(filterID: id, optionID: $0, name: label(id, $0), excluded: false)
                }
                    + excluded.map {
                        Applied(filterID: id, optionID: $0, name: label(id, $0), excluded: true)
                    }

            case .select(let id, let optionID):
                return [
                    Applied(
                        filterID: id, optionID: optionID, name: label(id, optionID), excluded: false
                    )
                ]

            case .number(let id, let value):
                return [
                    Applied(
                        filterID: id, optionID: String(value), name: "\(name(of: id)) \(value)",
                        excluded: false)
                ]

            case .text(let id, let value):
                guard !value.isEmpty else { return [] }
                return [Applied(filterID: id, optionID: value, name: value, excluded: false)]
            }
        }
    }

    func remove(_ chip: Applied) {
        guard let index = filters.firstIndex(where: { $0.id == chip.filterID }) else { return }
        defer { refreshGate() }

        switch filters[index] {
        case .multiSelect(let id, let included, let excluded):
            let remainingIncluded = included.filter { $0 != chip.optionID }
            let remainingExcluded = excluded.filter { $0 != chip.optionID }
            if remainingIncluded.isEmpty, remainingExcluded.isEmpty {
                filters.remove(at: index)
            } else {
                filters[index] = .multiSelect(
                    id: id, included: remainingIncluded, excluded: remainingExcluded)
            }

        case .select, .number, .text:
            filters.remove(at: index)
        }
    }

    private func label(_ filterID: String, _ optionID: String) -> String {
        for filter in supportedFilters {
            switch filter {
            case .select(let id, _, let options) where id == filterID:
                return options.first { $0.id == optionID }?.name ?? optionID
            case .multiSelect(let id, _, let options, _) where id == filterID:
                return options.first { $0.id == optionID }?.name ?? optionID
            default:
                continue
            }
        }
        return optionID
    }

    private func name(of filterID: String) -> String {
        for filter in supportedFilters {
            switch filter {
            case .text(let id, let name), .number(let id, let name),
                .select(let id, let name, _), .multiSelect(let id, let name, _, _):
                if id == filterID { return name }
            }
        }
        return filterID
    }

    func selectSort(_ optionID: String?) {
        guard let optionID else {
            sort = nil
            return
        }
        sort = SortSelection(optionID: optionID)
    }

    // true while nothing has been explicitly chosen, so the Automatic row can
    // show a checkmark
    var isDefaultSort: Bool { sort == nil }

    func selection(for id: String) -> FilterSelection? {
        filters.first { $0.id == id }
    }

    func setSelection(_ selection: FilterSelection?, for id: String) {
        filters.removeAll { $0.id == id }
        if let selection { filters.append(selection) }
        refreshGate()
    }

    // Clear All leaving a non-default sort applied with nothing on screen
    // saying so was the same bug the filter count had
    func clearFilters() {
        filters.removeAll()
        sort = nil
        refreshGate()
    }

    init(source: Source, preset: SourcePreset, database: DatabaseClient) {
        self.source = source
        self.preset = preset
        self.correlator = Correlator(sourceSlug: source.descriptor.slug, database: database)
        self.searchText = ""
        self.filters = preset.filters
        self.sort = preset.sort
        refreshGate()
    }

    init(source: Source, query: String, database: DatabaseClient) {
        self.source = source
        self.preset = nil
        self.correlator = Correlator(sourceSlug: source.descriptor.slug, database: database)
        self.searchText = query
        self.filters = []
        self.sort = nil
        // an adultOnly source opens the gate even with no filters ticked - this
        // must not be skipped just because filters are empty
        refreshGate()
    }

    init(source: Source, database: DatabaseClient) {
        self.source = source
        self.preset = nil
        self.correlator = Correlator(sourceSlug: source.descriptor.slug, database: database)
        self.searchText = ""
        self.filters = []
        self.sort = nil
        refreshGate()
    }

    private func refreshGate() {
        gateOpen = source.allowsAdult(
            for: SearchQuery(text: nil, filters: filters, sort: nil, page: 1))
    }

    func match(for stub: SeriesStub) -> SeriesMatch? {
        correlator[stub]
    }

    func startObserving() {
        observationTask?.cancel()
        correlator.observe(entries.map(\.stub))
        observationTask = Task { @MainActor in
            var previous = state
            if entries.isEmpty, !isIdle { triggerSearch() }

            while !Task.isCancelled {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { break }

                let current = state
                guard current != previous else { continue }
                previous = current

                guard !isIdle else {
                    searchTask?.cancel()
                    resetPagination()
                    continue
                }

                resetPagination()
                triggerSearch()
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
        guard !isLoading, !isLoadingMore, hasMore, failure == nil else { return }
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
                page: page,
                route: route
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
            failure = nil
            correlator.observe(entries.map(\.stub))
        } catch is CancellationError {
            if loadingMore, page > 1 { page -= 1 }
        } catch let urlError as URLError where urlError.code == .cancelled {
            if loadingMore, page > 1 { page -= 1 }
        } catch {
            if loadingMore, page > 1 { page -= 1 }
            failure = Failure(error, fallback: "Couldn't Load")
            AppLog.shared.log(
                "search failed for '\(source.descriptor.slug)' - \(error)", level: .error,
                category: "search")
        }

        if loadingMore { isLoadingMore = false } else { isLoading = false }
    }

    private func resetPagination() {
        page = 1
        entries = []
        hasMore = true
        failure = nil
    }
}

private struct SearchState: Equatable {
    let text: String
    let filters: [FilterSelection]
    let sort: SortSelection?
}

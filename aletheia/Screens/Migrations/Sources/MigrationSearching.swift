//
//  MigrationSearching.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// title search across a fixed set of already-installed sources, for a fixed
// title - not the live-typing debounced search SearchViewModel is built for,
// so this does not reuse that type, only the same source.search(_:) call it
// makes (Screens/Search/SearchViewModel.swift). shared by every migration
// flow unchanged - none of it is specific to where the title came from
protocol MigrationSearching: Sendable {
    func search(title: String, in sources: [Source]) async -> MigrationMatch
}

// a candidate is pre-selected when its title exactly matches (case- and
// diacritic-insensitive) and it is the only one that does - the same "an
// exact string match is worth trusting to pre-fill, never to silently
// commit" line trackers.md Q4 already draws. Save still requires its own tap
struct LiveMigrationSearcher: MigrationSearching {
    private let log: AppLog

    init(log: AppLog = .shared) {
        self.log = log
    }

    // a bounded wait per source, not a race-condition sleep: a migration
    // session fans out to every selected source at once, and one scraped
    // source with no timeout of its own must never hold up every other row
    // behind it
    private enum Timing {
        static let perSource: Duration = .seconds(15)
    }

    func search(title: String, in sources: [Source]) async -> MigrationMatch {
        guard !sources.isEmpty else { return .notFound }

        let query = SearchQuery(text: title, filters: [], sort: nil, page: 1)

        let results = await withTaskGroup(of: (String, Result<[SeriesStub], Error>).self) { group in
            for source in sources {
                group.addTask { [log] in
                    do {
                        let page = try await Self.withTimeout(Timing.perSource) {
                            try await source.search(query)
                        }
                        return (source.descriptor.slug, .success(page.items))
                    } catch {
                        log.log(
                            "migration search timed out or failed for '\(source.descriptor.slug)' - \(error)",
                            level: .error,
                            category: "migration"
                        )
                        return (source.descriptor.slug, .failure(error))
                    }
                }
            }

            var collected: [(String, Result<[SeriesStub], Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var candidates: [MigrationCandidate] = []
        var failureCount = 0

        for (sourceSlug, outcome) in results {
            switch outcome {
            case .success(let stubs):
                candidates.append(
                    contentsOf: stubs.map { MigrationCandidate(sourceSlug: sourceSlug, stub: $0) })
            case .failure:
                failureCount += 1
            }
        }

        guard failureCount < results.count else {
            return .failed("Every source failed to respond.")
        }

        guard !candidates.isEmpty else { return .notFound }

        let exact = candidates.filter {
            $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }

        let selected = exact.count == 1 ? exact.first : nil
        return .found(candidates, selected: selected)
    }

    private struct TimeoutError: Error {}

    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw TimeoutError() }
            return result
        }
    }
}

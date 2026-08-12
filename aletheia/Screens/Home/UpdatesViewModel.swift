//
//  UpdatesViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation

// the whole updates feed, where Home carries three rows of it. one query, the
// same one, at a different limit - two feeds that could disagree about what
// arrived would be worse than one that is sometimes long
@MainActor
@Observable
final class UpdatesViewModel {
    private let database: DatabaseClient
    private let assets: Compositor.Assets
    private let registry: Compositor.Registry

    private(set) var entries: [HomeViewModel.UpdateEntry]?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    private enum Rule {
        // a ceiling rather than a window: the feed is bounded by how many series
        // you follow, and a reader with more than this waiting is not served by
        // row two hundred
        static let limit = 200
    }

    init(database: DatabaseClient, assets: Compositor.Assets, registry: Compositor.Registry) {
        self.database = database
        self.assets = assets
        self.registry = registry
    }

    var isEmpty: Bool { entries?.isEmpty == true }

    func observe() {
        guard stream == nil else { return }
        let adultSlugs = AdultGate.slugs(in: registry)

        stream = Task { [weak self, database] in
            let observation = ValueObservation
                .tracking { db in
                    let excluded = try AdultGate.excluded(slugs: adultSlugs, in: db)
                    return try HomeViewModel.updating(excluded: excluded, limit: Rule.limit, in: db)
                }
                .removeDuplicates()

            do {
                for try await rows in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.entries = rows.map { self.entry($0) }
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Updates")
                AppLog.shared.log("updates observation failed - \(error)", level: .error, category: "home")
            }
        }
    }

    func retry() {
        stream?.cancel()
        stream = nil
        failure = nil
        observe()
    }

    private func entry(_ row: HomeViewModel.UpdateRow) -> HomeViewModel.UpdateEntry {
        HomeViewModel.UpdateEntry(
            id: SeriesRecord.ID(rawValue: row.entry.seriesId),
            title: row.entry.title,
            cover: assets.local(for: row.entry.path) ?? row.entry.cover,
            count: row.count,
            latest: row.latest,
            target: row.target,
            adult: row.entry.adult
        )
    }
}

// MARK: - Preview

#if DEBUG
extension UpdatesViewModel {
    static func preview(
        entries: [HomeViewModel.UpdateEntry]? = nil,
        failure: Failure? = nil
    ) -> UpdatesViewModel {
        let database = DatabaseClient.preview
        let registry = Compositor.Registry(sources: [], database: database)
        let model = UpdatesViewModel(
            database: database,
            assets: Compositor.Assets(database: database, registry: registry, network: NetworkService()),
            registry: registry
        )
        model.entries = entries
        model.failure = failure
        return model
    }
}
#endif

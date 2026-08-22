//
//  UpdatesViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB
import Observation
import Tagged

@MainActor
@Observable
final class UpdatesViewModel {
    private let database: DatabaseClient
    private let assets: Compositor.Assets
    private let registry: Compositor.Registry

    private(set) var entries: [HomeViewModel.UpdateEntry]?
    // raw publish dates, last 7 days - bucketed view-side via UpdateBuckets
    private(set) var activity: [Date]?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    private enum Rule {
        static let limit = 200
    }

    private struct Fetched: Equatable {
        let rows: [HomeViewModel.UpdateRow]
        let activity: [Date]
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
            let observation =
                ValueObservation
                .tracking { db -> Fetched in
                    let excluded =
                        try AdultGate.excluded(slugs: adultSlugs, in: db)
                        .union(CollectionGate.hiddenFromHome(in: db))
                    let since =
                        Calendar.current.date(
                            byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))
                        ?? .now

                    return Fetched(
                        rows: try HomeViewModel.updating(
                            excluded: excluded, limit: Rule.limit, in: db),
                        activity: try HomeViewModel.activity(
                            excluded: excluded, since: since, in: db)
                    )
                }
                .removeDuplicates()

            do {
                for try await fetched in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.entries = fetched.rows.map { self.entry($0) }
                    self.activity = fetched.activity
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Updates")
                AppLog.shared.log(
                    "updates observation failed - \(error)", level: .error, category: "home")
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
            activity: [Date]? = nil,
            failure: Failure? = nil
        ) -> UpdatesViewModel {
            let database = DatabaseClient.preview
            let registry = Compositor.Registry(sources: [], database: database)
            let model = UpdatesViewModel(
                database: database,
                assets: Compositor.Assets(
                    database: database, registry: registry, network: NetworkService()),
                registry: registry
            )
            model.entries = entries
            model.activity = activity
            model.failure = failure
            return model
        }
    }
#endif

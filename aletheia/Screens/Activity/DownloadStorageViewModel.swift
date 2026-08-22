//
//  DownloadStorageViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Foundation
import GRDB
import Observation
import Tagged

@MainActor
@Observable
final class DownloadStorageViewModel {
    private let database: DatabaseClient
    private let assets: Compositor.Assets

    private(set) var snapshot: [SeriesStorage]?
    private(set) var failure: Failure?

    @ObservationIgnored private var stream: Task<Void, Never>?

    init(database: DatabaseClient, assets: Compositor.Assets) {
        self.database = database
        self.assets = assets
    }

    func observe() {
        guard stream == nil else { return }
        stream = Task { [weak self, database, assets] in
            let observation =
                ValueObservation
                .tracking { db in
                    try Self.stored(in: db)
                }
                .removeDuplicates()

            do {
                for try await stored in observation.values(in: database.reader) {
                    guard let self, !Task.isCancelled else { break }
                    self.snapshot = stored.map { row in
                        SeriesStorage(
                            id: SeriesRecord.ID(rawValue: row.seriesId),
                            title: row.title,
                            cover: assets.local(for: row.coverPath) ?? row.cover,
                            bytes: row.bytes,
                            chapterCount: row.chapterCount
                        )
                    }
                    self.failure = nil
                }
            } catch {
                guard let self else { return }
                self.failure = Failure(error, fallback: "Couldn't Load Storage")
                AppLog.shared.log(
                    "download storage observation failed - \(error)", level: .error,
                    category: "downloads")
            }
        }
    }

    func retry() {
        stream?.cancel()
        stream = nil
        failure = nil
        observe()
    }

    // MARK: Query

    // folder names are a content hash of "originId/slug" - they carry no
    // series signal on their own, so grouping has to go through the db
    // rather than the filesystem's own layout
    nonisolated private static func stored(in db: Database) throws -> [Row] {
        let rows = try ChapterRow.fetchAll(
            db,
            sql: """
                SELECT
                    c.\(ChapterRecord.Columns.path.name) AS chapterPath,
                    o.\(OriginRecord.Columns.seriesId.name) AS seriesId,
                    e.\(EntryView.Columns.title.name) AS title,
                    e.\(EntryView.Columns.cover.name) AS cover,
                    e.\(EntryView.Columns.path.name) AS coverPath
                FROM \(ChapterRecord.databaseTableName) c
                JOIN \(OriginRecord.databaseTableName) o
                  ON o.id = c.\(ChapterRecord.Columns.originId.name)
                JOIN \(EntryView.databaseTableName) e
                  ON e.\(EntryView.Columns.seriesId.name) = o.\(OriginRecord.Columns.seriesId.name)
                WHERE c.\(ChapterRecord.Columns.path.name) IS NOT NULL
                """
        )

        var bySeriesId: [Int64: (title: String, cover: URL?, coverPath: String?, bytes: Int64, count: Int)] = [:]

        for row in rows {
            guard let url = Constants.Paths.resolve(row.chapterPath) else { continue }
            let size = Self.size(of: url)

            if var existing = bySeriesId[row.seriesId] {
                existing.bytes += size
                existing.count += 1
                bySeriesId[row.seriesId] = existing
            } else {
                bySeriesId[row.seriesId] = (row.title, row.cover, row.coverPath, size, 1)
            }
        }

        return bySeriesId
            .map { seriesId, value in
                Row(
                    seriesId: seriesId,
                    title: value.title,
                    cover: value.cover,
                    coverPath: value.coverPath,
                    bytes: value.bytes,
                    chapterCount: value.count
                )
            }
            .sorted { $0.bytes > $1.bytes }
    }

    // allocated, not logical, size - matches ActivityViewModel's own choice
    // for the whole-library total, scoped here to one chapter's folder
    nonisolated private static func size(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileAllocatedSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.fileAllocatedSizeKey, .isDirectoryKey]),
                values.isDirectory != true
            else { continue }

            total += Int64(values.fileAllocatedSize ?? 0)
        }
        return total
    }

    fileprivate struct ChapterRow: Decodable, FetchableRecord {
        let chapterPath: String
        let seriesId: Int64
        let title: String
        let cover: URL?
        let coverPath: String?
    }

    fileprivate struct Row: Sendable, Equatable {
        let seriesId: Int64
        let title: String
        let cover: URL?
        let coverPath: String?
        let bytes: Int64
        let chapterCount: Int
    }
}

// MARK: - SeriesStorage

struct SeriesStorage: Identifiable, Sendable, Equatable {
    let id: SeriesRecord.ID
    let title: String
    let cover: URL?
    let bytes: Int64
    let chapterCount: Int
}

// MARK: - Previews

#if DEBUG
    extension DownloadStorageViewModel {
        static func preview(snapshot: [SeriesStorage]? = nil, failure: Failure? = nil)
            -> DownloadStorageViewModel
        {
            let database = DatabaseClient.preview
            let registry = Compositor.Registry(sources: [], database: database)
            let model = DownloadStorageViewModel(
                database: database,
                assets: Compositor.Assets(
                    database: database, registry: registry, network: NetworkService())
            )
            model.snapshot = snapshot
            model.failure = failure
            return model
        }
    }
#endif

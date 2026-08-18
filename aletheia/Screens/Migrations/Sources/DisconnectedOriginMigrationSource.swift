//
//  DisconnectedOriginMigrationSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import GRDB
import Tagged

// every library series carrying a disconnected origin - sourceId IS NULL,
// the one and only meaning "disconnected" has in this codebase
// (DetailsComposer+Sources.swift's own Availability enum, LibraryFilter's
// detachedSource). "missing" (source row present, plugin not installed) is
// a different state and deliberately out of scope here
struct DisconnectedOriginMigrationSource: MigrationSource {
    let database: DatabaseClient

    func fetch() async throws -> [SourceMigrationEntry] {
        try await database.reader.read { db in
            let origins =
                try OriginRecord
                .filter(OriginRecord.Columns.sourceId == nil)
                .fetchAll(db)
            guard !origins.isEmpty else { return [] }

            let seriesIds = Set(origins.map { $0.seriesId.rawValue })
            let entries =
                try EntryView
                .filter(seriesIds.contains(EntryView.Columns.seriesId))
                .filter(EntryView.Columns.inLibrary == true)
                .fetchAll(db)
            let bySeriesId = Dictionary(uniqueKeysWithValues: entries.map { ($0.seriesId, $0) })

            return origins.compactMap { origin -> SourceMigrationEntry? in
                guard let originId = origin.id, let entry = bySeriesId[origin.seriesId.rawValue]
                else { return nil }
                return SourceMigrationEntry(
                    id: originId,
                    seriesId: origin.seriesId,
                    title: entry.title,
                    cover: entry.cover
                )
            }
        }
    }
}

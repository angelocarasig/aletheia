//
//  SeriesOnSourceMigrationSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import GRDB
import Tagged

struct SeriesOnSourceMigrationSource: MigrationSource {
    let sourceSlug: String
    let database: DatabaseClient

    func fetch() async throws -> [SourceMigrationEntry] {
        try await database.reader.read { db in
            guard
                let sourceId =
                    try SourceRecord
                    .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
                    .filter(SourceRecord.Columns.slug == sourceSlug)
                    .fetchOne(db)
            else { return [] }

            let origins =
                try OriginRecord
                .filter(OriginRecord.Columns.sourceId == sourceId.rawValue)
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

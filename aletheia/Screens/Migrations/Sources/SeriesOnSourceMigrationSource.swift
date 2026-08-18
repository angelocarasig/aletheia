//
//  SeriesOnSourceMigrationSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import GRDB
import Tagged

// every library series carrying an origin on one specific source - the
// bulk "move everything off source X" entry point. title/cover are read
// through EntryView rather than resolved by hand here, so a migration row
// shows the same preference-resolved title/cover Library and Details do
struct SeriesOnSourceMigrationSource: MigrationSource {
    // a slug rather than a resolved id - the only source identity a screen
    // has synchronously to hand, matching how selectedSourceSlugs already
    // identifies sources everywhere else in this feature family. resolved
    // to a real SourceRecord.ID here, inside the same async read that does
    // everything else
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

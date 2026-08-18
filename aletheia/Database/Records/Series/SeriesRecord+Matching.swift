//
//  SeriesRecord+Matching.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB

struct SeriesMatch: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case inLibrary(SeriesRecord.ID)
        case candidates([SeriesRecord.ID])
        case unmatched
    }

    let outcome: Outcome
    let existing: SeriesRecord.ID?
}

extension SeriesRecord {
    static func match(
        _ stubs: [SeriesStub],
        from sourceSlug: String,
        in db: Database
    ) throws -> [SeriesMatch] {
        guard !stubs.isEmpty else { return [] }

        let sourceId =
            try SourceRecord
            .select(SourceRecord.Columns.id, as: SourceRecord.ID.self)
            .filter(SourceRecord.Columns.slug == sourceSlug)
            .fetchOne(db)

        // an unseeded source has no origins to hit, but the title tier is
        // independent of source and still runs
        let origins =
            try sourceId.map { id in
                try OriginRecord
                    .filter(OriginRecord.Columns.sourceId == id)
                    .filter(stubs.map(\.slug).contains(OriginRecord.Columns.slug))
                    .fetchAll(db)
            } ?? []

        // the column collates case-insensitively, so IN already matches on case
        let titles =
            try TitleRecord
            .filter(stubs.map(\.title).contains(TitleRecord.Columns.value))
            .fetchAll(db)

        let touched = Set(origins.map(\.seriesId)).union(titles.map(\.seriesId))
        let library =
            try SeriesRecord
            .select(Columns.id, as: SeriesRecord.ID.self)
            .filter(touched.contains(Columns.id))
            .filter(Columns.inLibrary == true)
            .fetchSet(db)

        // unique(sourceId, slug) makes this one row per slug
        let bySlug = Dictionary(
            origins.map { ($0.slug, $0.seriesId) },
            uniquingKeysWith: { first, _ in first }
        )

        var byTitle: [String: [SeriesRecord.ID]] = [:]
        for title in titles where library.contains(title.seriesId) {
            byTitle[title.value.lowercased(), default: []].append(title.seriesId)
        }

        return stubs.map { stub in
            var existing: SeriesRecord.ID?

            // a slug hit only ends the search when it is already in the library.
            // otherwise it is carried forward and the title tier still runs, so a
            // series held under another source is never missed
            if let hit = bySlug[stub.slug] {
                if library.contains(hit) {
                    return SeriesMatch(outcome: .inLibrary(hit), existing: nil)
                }
                existing = hit
            }

            let candidates = byTitle[stub.title.lowercased()] ?? []

            return SeriesMatch(
                outcome: candidates.isEmpty ? .unmatched : .candidates(candidates),
                existing: existing
            )
        }
    }

    static func match(
        _ stub: SeriesStub,
        from sourceSlug: String,
        in db: Database
    ) throws -> SeriesMatch {
        try match([stub], from: sourceSlug, in: db)[0]
    }
}

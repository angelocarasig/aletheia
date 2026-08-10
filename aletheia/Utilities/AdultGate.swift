//
//  AdultGate.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import GRDB

// which series an adult-only source put in the library, and whether a surface is
// meant to see them. adultOnly is a descriptor fact the database cannot see, so
// the slugs come from the registry and the exclusion rides into the query.
//
// it applies to the two surfaces someone else can see over your shoulder - Home
// and Library - and deliberately not to Activity or Reading Activity. those are
// a record of what you read, and a total that quietly omits some of it is not a
// smaller total, it is a wrong one
enum AdultGate {
    static func slugs(in registry: Compositor.Registry) -> [String] {
        guard !UserDefaults.standard.bool(forKey: Preferences.Key.bypassAdultSources) else {
            return []
        }
        return registry.sources.filter(\.descriptor.adultOnly).map(\.descriptor.slug)
    }

    // any origin from one of these sources excludes the whole series, even where
    // another source also carries it: the question is whether the row can appear
    // at all, and one adult origin is enough to answer it
    static func excluded(slugs: [String], in db: Database) throws -> Set<Int64> {
        guard !slugs.isEmpty else { return [] }

        let marks = slugs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT DISTINCT o.\(OriginRecord.Columns.seriesId.name)
            FROM \(OriginRecord.databaseTableName) o
            JOIN \(SourceRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.sourceId.name)
            WHERE s.\(SourceRecord.Columns.slug.name) IN (\(marks))
            """
        return Set(try Int64.fetchAll(db, sql: sql, arguments: StatementArguments(slugs)))
    }
}

//
//  CollectionGate.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Foundation
import GRDB

// mirrors AdultGate's shape - a series in any collection flagged hideFromHome
// excludes it from every Home area, same "one is enough" reasoning
enum CollectionGate {
    static func hiddenFromHome(in db: Database) throws -> Set<Int64> {
        let sql = """
            SELECT DISTINCT sc.\(SeriesCollectionRecord.Columns.seriesId.name)
            FROM \(SeriesCollectionRecord.databaseTableName) sc
            JOIN \(CollectionRecord.databaseTableName) c
              ON c.id = sc.\(SeriesCollectionRecord.Columns.collectionId.name)
            WHERE c.\(CollectionRecord.Columns.hideFromHome.name) = 1
            """
        return Set(try Int64.fetchAll(db, sql: sql))
    }
}

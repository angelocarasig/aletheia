//
//  StorableRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB

// url and path are not two spellings of the same thing. for a cover, url is the
// downloadable asset itself; for a chapter, url is the page a reader would
// open, not an image - its pages come from the source instead. path is where
// the bytes landed locally. nothing may assume url is directly downloadable
protocol StorableRecord: DatabaseRecord {
    var url: URL { get }
    var path: String? { get set }

    static var storage: URL { get }
    static var pathColumn: Column { get }
}

extension StorableRecord {
    static func stored(in db: Database) throws -> Set<String> {
        let paths = try String.fetchAll(
            db,
            sql:
                "SELECT \(pathColumn.name) FROM \(databaseTableName) WHERE \(pathColumn.name) IS NOT NULL"
        )
        return Set(paths)
    }

    static func forget(_ paths: [String], in db: Database) throws {
        guard !paths.isEmpty else { return }
        try filter(paths.contains(pathColumn)).updateAll(db, pathColumn.set(to: nil as String?))
    }
}

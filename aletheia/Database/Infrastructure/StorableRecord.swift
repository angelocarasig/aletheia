//
//  StorableRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB

// a record whose bytes can live on disk as well as in the database.
//
// url and path are not two spellings of the same thing. url is where the record
// lives on the web - for a cover that is the downloadable asset itself, for a
// chapter it is the page a reader would open, and its actual images come from
// the source. path is where the bytes landed locally, relative to the app group
// container. nothing may assume url is directly downloadable
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
            sql: "SELECT \(pathColumn.name) FROM \(databaseTableName) WHERE \(pathColumn.name) IS NOT NULL"
        )
        return Set(paths)
    }

    static func forget(_ paths: [String], in db: Database) throws {
        guard !paths.isEmpty else { return }
        try filter(paths.contains(pathColumn)).updateAll(db, pathColumn.set(to: nil as String?))
    }
}

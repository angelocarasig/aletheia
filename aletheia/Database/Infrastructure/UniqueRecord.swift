//
//  UniqueRecord.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import GRDB

protocol UniqueRecord: DatabaseRecord {
    static func uniqueFilter(for instance: Self) -> QueryInterfaceRequest<Self>
}

extension UniqueRecord {
    static func findOrCreate(_ instance: Self, in db: Database) throws -> Self
    where Self: MutablePersistableRecord {
        if let existing = try Self.uniqueFilter(for: instance).fetchOne(db) {
            return existing
        }
        var mutableInstance = instance
        try mutableInstance.insert(db)
        return mutableInstance
    }
}

//
//  CollectionSettingsViewModel.swift
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
final class CollectionSettingsViewModel {
    private let database: DatabaseClient

    private(set) var collections: [CollectionRecord] = []
    private(set) var isLoading = false

    init(database: DatabaseClient) {
        self.database = database
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        collections =
            (try? await database.reader.read { db in
                try CollectionRecord.order(CollectionRecord.Columns.name.asc).fetchAll(db)
            }) ?? []
    }

    func setHideFromHome(_ value: Bool, for id: CollectionRecord.ID) async {
        try? await database.writer.write { db in
            _ =
                try CollectionRecord
                .filter(key: id.rawValue)
                .updateAll(db, CollectionRecord.Columns.hideFromHome.set(to: value))
        }
        await load()
    }

    func setRequiresFaceId(_ value: Bool, for id: CollectionRecord.ID) async {
        try? await database.writer.write { db in
            _ =
                try CollectionRecord
                .filter(key: id.rawValue)
                .updateAll(db, CollectionRecord.Columns.requiresFaceId.set(to: value))
        }
        await load()
    }
}

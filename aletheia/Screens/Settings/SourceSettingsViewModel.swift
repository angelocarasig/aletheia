//
//  SourceSettingsViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Foundation
import GRDB
import Observation
import SwiftUI
import Tagged

@MainActor
@Observable
final class SourceSettingsViewModel {
    private let database: DatabaseClient
    private let registry: Compositor.Registry

    var bypassAdult = Preferences.Default.bypassAdultSources

    private(set) var all: [SourceRecord] = []
    private(set) var isLoading = false

    // the tick gate applies here too - an adult-only source stays out of this
    // list entirely until bypassed, same as everywhere else it's listed
    var sources: [SourceRecord] {
        bypassAdult ? all : all.filter { !isAdult($0) }
    }

    init(database: DatabaseClient, registry: Compositor.Registry) {
        self.database = database
        self.registry = registry
    }

    func icon(for source: SourceRecord) -> ImageResource? {
        registry.source(slug: source.slug)?.descriptor.icon
    }

    private func isAdult(_ record: SourceRecord) -> Bool {
        registry.source(slug: record.slug)?.descriptor.adultOnly == true
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        all =
            (try? await database.reader.read { db in
                try SourceRecord
                    .filter(SourceRecord.Columns.installed == true)
                    .order(SourceRecord.Columns.name.asc)
                    .fetchAll(db)
            }) ?? []
    }

    func setHideFromSearch(_ value: SearchVisibility, for id: SourceRecord.ID) async {
        try? await database.writer.write { db in
            _ =
                try SourceRecord
                .filter(key: id.rawValue)
                .updateAll(db, SourceRecord.Columns.hideFromSearch.set(to: value.rawValue))
        }
        await load()
    }

    func setRequiresFaceId(_ value: Bool, for id: SourceRecord.ID) async {
        try? await database.writer.write { db in
            _ =
                try SourceRecord
                .filter(key: id.rawValue)
                .updateAll(db, SourceRecord.Columns.requiresFaceId.set(to: value))
        }
        await load()
    }
}

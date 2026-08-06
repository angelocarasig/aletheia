//
//  LibraryViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB
import Tagged
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private let database: DatabaseClient

    private(set) var entries: [Entry] = []
    private(set) var isLoading = false

    init(database: DatabaseClient = .client) {
        self.database = database
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let rows = try? await database.reader.read { db in
            try EntryView
                .filter(EntryView.Columns.inLibrary == true)
                .order(EntryView.Columns.addedDate.desc)
                .fetchAll(db)
        }

        entries = (rows ?? []).map {
            Entry(id: SeriesRecord.ID(rawValue: $0.seriesId), title: $0.title, cover: $0.cover, unreadCount: $0.unreadCount)
        }
    }
}

extension LibraryViewModel {
    struct Entry: Identifiable, Hashable {
        let id: SeriesRecord.ID
        let title: String
        let cover: URL?
        let unreadCount: Int
    }
}

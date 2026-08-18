//
//  DetailsComposer+Library.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Observation
import Tagged

extension DetailsComposer {
    @MainActor
    @Observable
    final class Library: DetailsApplying, DetailsWriting {
        private(set) var inLibrary = false
        private(set) var status: Status = .planning

        // TODO: the view still declares its own copy of this row - CollectionPicker
        // switches to this one when the screen is wired
        private(set) var collections: [Collection] = []

        private(set) var saving = false
        private(set) var failure: Failure?

        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        private let database: DatabaseClient

        init(database: DatabaseClient) {
            self.database = database
        }

        func apply(_ stored: Stored) {
            seriesId = stored.series.id

            // off the series row, not the entry view - the two can never
            // disagree this way
            inLibrary = stored.series.inLibrary
            status = stored.series.status

            let mapped = stored.collections.map {
                Collection(id: $0.id, name: $0.name, count: $0.count, contains: $0.contains)
            }
            if collections != mapped { collections = mapped }
        }

        func clear() {
            failure = nil
        }

        var joined: [Collection] {
            collections.filter(\.contains)
        }

        var canToggle: Bool {
            seriesId != nil && !saving
        }

        // returns whether the write landed - adding opens the setup flow over
        // the top, and that must not appear on a failed add
        @discardableResult
        func toggle() async -> Bool {
            guard let seriesId else { return false }

            saving = true
            defer { saving = false }

            let value = !inLibrary

            do {
                try await database.writer.write { db in
                    try Self.set(inLibrary: value, for: seriesId, in: db)
                }
                return true
            } catch {
                failure = Failure(error, fallback: "Couldn't Update Library")
                return false
            }
        }

        func toggle(collection id: Int64) async {
            saving = true
            defer { saving = false }

            await join(id)
        }

        // also set for the reader when they open a chapter, via Chapters.open()
        func set(status value: Status) async {
            guard let seriesId, value != status else { return }

            saving = true
            defer { saving = false }

            do {
                try await database.writer.write { db in
                    _ =
                        try SeriesRecord
                        .filter(key: seriesId.rawValue)
                        .updateAll(db, SeriesRecord.Columns.status.set(to: value.rawValue))
                }
            } catch {
                failure = Failure(error, fallback: "Couldn't Update Status")
            }
        }

        // written empty first, so the sheet closes on a collection that
        // already exists rather than one pending a second write
        func create(
            collection name: String,
            description: String?,
            joining: Bool
        ) async {
            saving = true
            defer { saving = false }

            do {
                let id = try await database.writer.write { db -> Int64 in
                    var collection = CollectionRecord(name: name, description: description)
                    try collection.insert(db)

                    guard let id = collection.id else { throw RecordError.missingIdentifier }
                    return id.rawValue
                }

                if joining { await join(id) }
            } catch {
                failure = Failure(error, fallback: "Couldn't Create Collection")
            }
        }

        // no saving flag here - create() holds it across both the insert and
        // the join, so setting it again here would clear it mid-flow
        private func join(_ id: Int64) async {
            guard let seriesId else {
                AppLog.shared.log(
                    "collection \(id) toggle skipped - no series yet", level: .warning,
                    category: "details")
                return
            }

            let collectionId = CollectionRecord.ID(rawValue: id)

            do {
                try await database.writer.write { db in
                    let existing =
                        try SeriesCollectionRecord
                        .filter(SeriesCollectionRecord.Columns.seriesId == seriesId)
                        .filter(SeriesCollectionRecord.Columns.collectionId == collectionId)
                        .fetchOne(db)

                    if let existing {
                        try existing.delete(db)
                        return
                    }

                    // query interface, not raw sql - "order" is a reserved
                    // keyword and would need escaping
                    let highest =
                        try SeriesCollectionRecord
                        .filter(SeriesCollectionRecord.Columns.collectionId == collectionId)
                        .select(max(SeriesCollectionRecord.Columns.order), as: Int.self)
                        .fetchOne(db) ?? nil

                    var link = SeriesCollectionRecord(
                        id: nil,
                        seriesId: seriesId,
                        collectionId: collectionId,
                        order: (highest ?? -1) + 1
                    )
                    try link.insert(db)
                }
                AppLog.shared.log(
                    "collection \(id) toggled for series \(seriesId.rawValue)", category: "details")
            } catch {
                failure = Failure(error, fallback: "Couldn't Update Collection")
                AppLog.shared.log(
                    "collection \(id) toggle FAILED - \(error)", level: .error, category: "details")
            }
        }
    }
}

extension DetailsComposer.Library {
    struct Collection: Identifiable, Hashable {
        let id: Int64
        let name: String
        let count: Int
        let contains: Bool
    }

    nonisolated static func set(
        inLibrary value: Bool,
        for id: SeriesRecord.ID,
        in db: Database
    ) throws {
        _ =
            try SeriesRecord
            .filter(key: id.rawValue)
            .updateAll(
                db,
                SeriesRecord.Columns.inLibrary.set(to: value),
                SeriesRecord.Columns.addedDate.set(to: value ? Date.now : Date.distantPast)
            )
    }

    nonisolated static func adopt(
        from source: SeriesRecord.ID,
        into target: SeriesRecord.ID,
        in db: Database
    ) throws {
        let links =
            try SeriesCollectionRecord
            .filter(SeriesCollectionRecord.Columns.seriesId == source)
            .fetchAll(db)

        for link in links {
            let highest =
                try SeriesCollectionRecord
                .filter(SeriesCollectionRecord.Columns.collectionId == link.collectionId)
                .select(max(SeriesCollectionRecord.Columns.order), as: Int.self)
                .fetchOne(db) ?? nil

            var adopted = SeriesCollectionRecord(
                id: nil,
                seriesId: target,
                collectionId: link.collectionId,
                order: (highest ?? -1) + 1
            )
            try adopted.insert(db, onConflict: .ignore)
        }
    }
}

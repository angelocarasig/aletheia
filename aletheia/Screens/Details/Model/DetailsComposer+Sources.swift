//
//  DetailsComposer+Sources.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Observation
import Tagged

import struct SwiftUI.ImageResource

extension DetailsComposer {
    @MainActor
    @Observable
    final class Sources: DetailsApplying, DetailsWriting {
        // unavailable sources stay in the list and sort last, rather than
        // being hidden
        private(set) var origins: [Origin] = []

        // read on present, not from the bundle - both sheets need rows the
        // screen's own list excludes, since a language or scanlator winning
        // nothing right now still has to be rankable
        private(set) var languageOrder: [Language] = []
        private(set) var scanlatorOrder: [Group] = []
        private(set) var isLoadingLanguages = false
        private(set) var isLoadingScanlators = false

        private(set) var writing: Set<Int64> = []

        var saving: Bool { !writing.isEmpty }
        private(set) var failure: Failure?

        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        private let registry: Compositor.Registry
        private let database: DatabaseClient

        init(registry: Compositor.Registry, database: DatabaseClient) {
            self.registry = registry
            self.database = database
        }

        func apply(_ stored: Stored) {
            seriesId = stored.series.id

            let mapped = stored.origins.map { row in
                // only the icon needs the registry - a compiled asset, not
                // stored data, unlike the rest of this row
                Origin(
                    id: row.id,
                    name: row.sourceName ?? row.sourceSlug ?? "Unknown Source",
                    slug: row.slug,
                    sourceSlug: row.sourceSlug,
                    host: row.sourceBaseURL?.host() ?? row.sourceSlug ?? "",
                    url: URL(string: row.url),
                    icon: row.sourceSlug.flatMap { registry.source(slug: $0) }?.descriptor.icon,
                    priority: row.priority,
                    chapterCount: row.chapterCount,
                    fetchedDate: row.chaptersFetchedDate > .distantPast
                        ? row.chaptersFetchedDate : nil,
                    availability: Self.availability(of: row),
                    failureReason: row.fetchError,
                    failedDate: row.fetchAttemptedDate > .distantPast ? row.fetchAttemptedDate : nil
                )
            }

            if origins != mapped { origins = mapped }
        }

        func clear() {
            failure = nil
        }

        func promote(_ originId: Int64) async {
            let target = OriginRecord.ID(rawValue: originId)

            await arrange([originId]) { ordered in
                guard let index = ordered.firstIndex(of: target) else { return ordered }
                var moved = ordered
                moved.insert(moved.remove(at: index), at: 0)
                return moved
            }
        }

        // trusted rather than diffed - anything the sheet left out keeps its
        // place at the end
        func reorder(_ ids: [Int64]) async {
            let arranged = ids.map { OriginRecord.ID(rawValue: $0) }

            await arrange(ids) { ordered in
                arranged + ordered.filter { !arranged.contains($0) }
            }
        }

        // the last source cannot go. chapters cascade away with it, but its
        // titles and covers stay in the pool with a null originId - a name the
        // reader picked is not ours to take back
        func remove(_ originId: Int64) async {
            guard let seriesId, origins.count > 1 else { return }
            let target = OriginRecord.ID(rawValue: originId)

            writing.insert(originId)
            defer { writing.remove(originId) }

            do {
                try await database.writer.write { db in
                    _ = try OriginRecord.filter(key: target.rawValue).deleteAll(db)
                    try Self.renumber(for: seriesId, in: db)
                }
                AppLog.shared.log("origin \(originId) removed", category: "details")
            } catch {
                failure = Failure(error, fallback: "Couldn't Remove Source")
                AppLog.shared.log(
                    "origin \(originId) remove FAILED - \(error)", level: .error,
                    category: "details")
            }
        }

        // order is read fresh inside the transaction and handed to the caller
        // to rework, so a sheet built before a source was removed still
        // commits against what is there now
        private func arrange(
            _ marked: [Int64],
            _ transform: @escaping ([OriginRecord.ID]) -> [OriginRecord.ID]
        ) async {
            guard let seriesId else { return }

            writing.formUnion(marked)
            defer { writing.subtract(marked) }

            do {
                try await database.writer.write { db in
                    let ordered = try Self.ordered(for: seriesId, in: db)
                    try Self.assign(transform(ordered), in: db)
                }
            } catch {
                failure = Failure(error, fallback: "Couldn't Reorder Sources")
                AppLog.shared.log(
                    "origin reorder FAILED - \(error)", level: .error, category: "details")
            }
        }

        // unranked languages sort last here - which is where best_chapter puts
        // them too
        func languages() async {
            guard let seriesId, !isLoadingLanguages else { return }

            isLoadingLanguages = true
            defer { isLoadingLanguages = false }

            do {
                languageOrder = try await database.reader.read { db in
                    try Self.languages(for: seriesId, in: db)
                }
            } catch {
                // a background load - keeps what it has rather than nagging
                AppLog.shared.log("languages failed - \(error)", level: .error, category: "details")
            }
        }

        // a commit is a swap within the slots the listed languages already
        // hold - they take each other's priorities, sorted ascending, and
        // every unlisted language keeps its place. no priority is ever minted
        // or duplicated
        func reorder(languages codes: [String]) async {
            guard let seriesId else { return }

            writing.formUnion(origins.map(\.id))
            defer { writing.subtract(origins.map(\.id)) }

            do {
                try await database.writer.write { db in
                    // a series from before seeding may lack rows to swap
                    try SeriesLanguagePriorityRecord.seedDefaults(for: seriesId, in: db)

                    let rows =
                        try SeriesLanguagePriorityRecord
                        .filter(SeriesLanguagePriorityRecord.Columns.seriesId == seriesId)
                        .fetchAll(db)
                    let byLanguage = Dictionary(
                        uniqueKeysWithValues: rows.map { ($0.language, $0) })

                    let ordered = codes.compactMap(LanguageCode.init)
                    let slots = ordered.compactMap { byLanguage[$0]?.priority }.sorted()
                    guard slots.count == ordered.count else { return }

                    for (slot, language) in zip(slots, ordered) {
                        guard var row = byLanguage[language], row.priority != slot else { continue }
                        row.priority = slot
                        try row.update(db)
                    }
                }
                await languages()
            } catch {
                failure = Failure(error, fallback: "Couldn't Reorder Languages")
                AppLog.shared.log(
                    "language reorder FAILED - \(error)", level: .error, category: "details")
            }
        }

        func scanlators() async {
            guard let seriesId, !isLoadingScanlators else { return }

            isLoadingScanlators = true
            defer { isLoadingScanlators = false }

            do {
                let rows = try await database.reader.read { db in
                    try Self.scanlators(for: seriesId, in: db)
                }
                scanlatorOrder = Self.group(rows, into: origins)
            } catch {
                AppLog.shared.log(
                    "scanlators failed - \(error)", level: .error, category: "details")
            }
        }

        // every row is written, not just the moved ones - a hole in the
        // sequence would let the unranked (999) fallback rearrange things
        // behind the reader
        func reorder(scanlators ids: [Int64], in originId: Int64) async {
            writing.insert(originId)
            defer { writing.remove(originId) }

            do {
                try await database.writer.write { db in
                    for (index, id) in ids.enumerated() {
                        var row = OriginScanlatorPriorityRecord(
                            originId: OriginRecord.ID(rawValue: originId),
                            scanlatorId: ScanlatorRecord.ID(rawValue: id),
                            priority: index
                        )
                        try row.upsert(db)
                    }
                }
                await scanlators()
            } catch {
                failure = Failure(error, fallback: "Couldn't Reorder Groups")
                AppLog.shared.log(
                    "scanlator reorder FAILED - \(error)", level: .error, category: "details")
            }
        }
    }
}

extension DetailsComposer.Sources {
    struct Origin: Identifiable, Hashable {
        let id: Int64
        let name: String
        let slug: String
        // the machine identifier a source is looked up by, distinct from
        // `name`'s display text - resetSeries() needs this to find the
        // installed Source again, which a display string isn't guaranteed to be
        let sourceSlug: String?
        let host: String
        let url: URL?
        let icon: ImageResource?
        let priority: Int
        let chapterCount: Int
        let fetchedDate: Date?
        let availability: Availability
        // the last attempt's error, cleared the moment the source answers
        // again - so this is what is wrong now, never what once was
        let failureReason: String?
        let failedDate: Date?

        var unavailable: Bool { availability != .available }

        // a source the user switched off is not a source that is failing
        var failing: Bool { failureReason != nil && availability == .available }

        // disabled is the user's own doing, disconnected means the source row
        // went away, missing means it is no longer compiled into the app
        enum Availability {
            case available, disabled, disconnected, missing
        }
    }

    struct Language: Identifiable, Hashable {
        let id: String
        let flag: String
        let name: String
        let chapterCount: Int
    }

    // ranking happens inside a group, never across them - a scanlator belongs
    // to the site that published it
    struct Group: Identifiable, Hashable {
        let id: Int64
        let name: String
        let icon: ImageResource?
        var scanlators: [Scanlator]
    }

    struct Scanlator: Identifiable, Hashable {
        let id: Int64
        let name: String
        let chapterCount: Int
    }

    nonisolated static func availability(
        of row: DetailsComposer.Stored.Origin
    ) -> Origin.Availability {
        if row.disconnected {
            .disconnected
        } else if !row.installed {
            .missing
        } else if row.disabled {
            .disabled
        } else {
            .available
        }
    }

    // rows are seeded at creation, so a missing one is a gap to heal rather
    // than an absence to rank around
    nonisolated static func languages(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [Language] {
        // straight off the base tables, not best_chapter: a language that
        // currently wins nothing is exactly the one you came here to promote
        let sql = """
            SELECT
                c.\(ChapterRecord.Columns.language.name) AS code,
                COUNT(c.id) AS chapterCount
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            LEFT JOIN \(SeriesLanguagePriorityRecord.databaseTableName) slp
                ON slp.\(SeriesLanguagePriorityRecord.Columns.seriesId.name) = o.\(OriginRecord.Columns.seriesId.name)
                AND slp.\(SeriesLanguagePriorityRecord.Columns.language.name) = c.\(ChapterRecord.Columns.language.name)
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            GROUP BY c.\(ChapterRecord.Columns.language.name)
            ORDER BY
                COALESCE(MIN(slp.\(SeriesLanguagePriorityRecord.Columns.priority.name)), 999) ASC,
                c.\(ChapterRecord.Columns.language.name) ASC
            """

        return
            try LanguageRow
            .fetchAll(db, sql: sql, arguments: [id.rawValue])
            .compactMap { row in
                guard let code = LanguageCode(rawValue: row.code) else { return nil }

                return Language(
                    id: code.rawValue,
                    flag: code.flag,
                    name: code.displayName,
                    chapterCount: row.chapterCount
                )
            }
    }

    private struct LanguageRow: Decodable, FetchableRecord, Sendable {
        let code: String
        let chapterCount: Int
    }

    nonisolated static func scanlators(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [ScanlatorRow] {
        // no best_chapter here either: a scanlator that currently loses every
        // chapter is exactly the one you open this sheet to promote
        let sql = """
            SELECT
                o.id AS originId,
                s.id AS scanlatorId,
                s.\(ScanlatorRecord.Columns.name.name) AS name,
                COUNT(c.id) AS chapterCount
            FROM \(ChapterRecord.databaseTableName) c
            JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
            JOIN \(ScanlatorRecord.databaseTableName) s ON s.id = c.\(ChapterRecord.Columns.scanlatorId.name)
            LEFT JOIN \(OriginScanlatorPriorityRecord.databaseTableName) osp
                ON osp.\(OriginScanlatorPriorityRecord.Columns.originId.name) = o.id
                AND osp.\(OriginScanlatorPriorityRecord.Columns.scanlatorId.name) = s.id
            WHERE o.\(OriginRecord.Columns.seriesId.name) = ?
            GROUP BY o.id, s.id
            ORDER BY
                o.\(OriginRecord.Columns.priority.name) ASC,
                COALESCE(MIN(osp.\(OriginScanlatorPriorityRecord.Columns.priority.name)), 999) ASC,
                s.\(ScanlatorRecord.Columns.name.name) ASC
            """

        return try ScanlatorRow.fetchAll(db, sql: sql, arguments: [id.rawValue])
    }

    struct ScanlatorRow: Decodable, FetchableRecord, Sendable {
        let originId: Int64
        let scanlatorId: Int64
        let name: String
        let chapterCount: Int
    }

    // not re-sorted - the query's own ordering (origin priority between
    // groups, scanlator priority within one) is what this relies on
    nonisolated static func group(
        _ rows: [ScanlatorRow],
        into origins: [Origin]
    ) -> [Group] {
        var groups: [Group] = []

        for row in rows {
            let scanlator = Scanlator(
                id: row.scanlatorId,
                name: row.name,
                chapterCount: row.chapterCount
            )

            if let index = groups.firstIndex(where: { $0.id == row.originId }) {
                groups[index].scanlators.append(scanlator)
            } else {
                let origin = origins.first { $0.id == row.originId }

                groups.append(
                    Group(
                        id: row.originId,
                        name: origin?.name ?? "Unknown Source",
                        icon: origin?.icon,
                        scanlators: [scanlator]
                    )
                )
            }
        }

        return groups
    }

    nonisolated static func ordered(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws -> [OriginRecord.ID] {
        try OriginRecord
            .select(OriginRecord.Columns.id, as: OriginRecord.ID.self)
            .filter(OriginRecord.Columns.seriesId == id)
            .order(OriginRecord.Columns.priority.asc, OriginRecord.Columns.id.asc)
            .fetchAll(db)
    }

    // lower wins - position 0 is the source that supplies a chapter when more
    // than one carries it, and the source the reader opens by default
    nonisolated static func assign(
        _ ordered: [OriginRecord.ID],
        in db: Database
    ) throws {
        for (position, id) in ordered.enumerated() {
            _ =
                try OriginRecord
                .filter(key: id.rawValue)
                .updateAll(db, OriginRecord.Columns.priority.set(to: position))
        }
    }

    // nothing stops two origins sharing a priority, but keeping them
    // consecutive means (priority, id) always sorts the way the list reads
    nonisolated static func renumber(
        for id: SeriesRecord.ID,
        in db: Database
    ) throws {
        try assign(try ordered(for: id, in: db), in: db)
    }
}

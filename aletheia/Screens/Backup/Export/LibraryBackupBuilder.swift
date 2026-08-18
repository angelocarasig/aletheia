//
//  LibraryBackupBuilder.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import GRDB
import Tagged

// one read transaction so the snapshot is internally consistent
enum LibraryBackupBuilder {
    static func build(database: DatabaseClient) async throws -> LibraryBackup {
        try await database.reader.read { db in try build(in: db) }
    }

    static func summary(database: DatabaseClient) async throws -> LibraryBackupSummary {
        try await database.reader.read { db in
            let seriesCount =
                try SeriesRecord
                .filter(SeriesRecord.Columns.inLibrary == true)
                .fetchCount(db)

            let chapterCount =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM \(ChapterRecord.databaseTableName) c
                        JOIN \(OriginRecord.databaseTableName) o ON o.id = c.\(ChapterRecord.Columns.originId.name)
                        JOIN \(SeriesRecord.databaseTableName) s ON s.id = o.\(OriginRecord.Columns.seriesId.name)
                        WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1
                        """
                ) ?? 0

            let tagCount =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(DISTINCT st.\(SeriesTagRecord.Columns.tagId.name))
                        FROM \(SeriesTagRecord.databaseTableName) st
                        JOIN \(SeriesRecord.databaseTableName) s ON s.id = st.\(SeriesTagRecord.Columns.seriesId.name)
                        WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1
                        """
                ) ?? 0

            let authorCount =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(DISTINCT sa.\(SeriesAuthorRecord.Columns.authorId.name))
                        FROM \(SeriesAuthorRecord.databaseTableName) sa
                        JOIN \(SeriesRecord.databaseTableName) s ON s.id = sa.\(SeriesAuthorRecord.Columns.seriesId.name)
                        WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1
                        """
                ) ?? 0

            let collectionCount = try CollectionRecord.fetchCount(db)

            let trackerLinkCount =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM \(SeriesTrackerRecord.databaseTableName) t
                        JOIN \(SeriesRecord.databaseTableName) s ON s.id = t.\(SeriesTrackerRecord.Columns.seriesId.name)
                        WHERE s.\(SeriesRecord.Columns.inLibrary.name) = 1
                        """
                ) ?? 0

            return LibraryBackupSummary(
                seriesCount: seriesCount,
                chapterCount: chapterCount,
                tagCount: tagCount,
                authorCount: authorCount,
                collectionCount: collectionCount,
                trackerLinkCount: trackerLinkCount
            )
        }
    }

    private static func build(in db: Database) throws -> LibraryBackup {
        let series =
            try SeriesRecord
            .filter(SeriesRecord.Columns.inLibrary == true)
            .fetchAll(db)
        let seriesIds = series.compactMap(\.id)

        // resolved titles, reusing EntryView's own preference->primary
        // origin->any COALESCE rather than re-deriving it here
        let titlesBySeriesId = Dictionary(
            uniqueKeysWithValues:
                try EntryView
                .filter(seriesIds.map(\.rawValue).contains(EntryView.Columns.seriesId))
                .fetchAll(db)
                .map { ($0.seriesId, $0.title) }
        )

        let origins =
            try OriginRecord
            .filter(seriesIds.contains(OriginRecord.Columns.seriesId))
            .fetchAll(db)
        let originIds = origins.compactMap(\.id)

        let sourceSlugsById = Dictionary(
            uniqueKeysWithValues: try SourceRecord.fetchAll(db).compactMap { source in
                source.id.map { ($0, source.slug) }
            }
        )

        let chapters =
            try ChapterRecord
            .filter(originIds.contains(ChapterRecord.Columns.originId))
            .fetchAll(db)
        let chaptersByOriginId = Dictionary(grouping: chapters, by: \.originId)

        let scanlatorNamesById = Dictionary(
            uniqueKeysWithValues: try ScanlatorRecord.fetchAll(db).compactMap { scanlator in
                scanlator.id.map { ($0, scanlator.name) }
            }
        )

        let seriesTags =
            try SeriesTagRecord
            .filter(seriesIds.contains(SeriesTagRecord.Columns.seriesId))
            .fetchAll(db)
        let tagNamesById = Dictionary(
            uniqueKeysWithValues: try TagRecord.fetchAll(db).compactMap { tag in
                tag.id.map { ($0, tag.displayName) }
            }
        )
        let tagNamesBySeriesId = Dictionary(
            grouping: seriesTags,
            by: \.seriesId
        ).mapValues { rows in rows.compactMap { tagNamesById[$0.tagId] } }

        let seriesAuthors =
            try SeriesAuthorRecord
            .filter(seriesIds.contains(SeriesAuthorRecord.Columns.seriesId))
            .fetchAll(db)
        let authorNamesById = Dictionary(
            uniqueKeysWithValues: try AuthorRecord.fetchAll(db).compactMap { author in
                author.id.map { ($0, author.name) }
            }
        )
        let authorNamesBySeriesId = Dictionary(
            grouping: seriesAuthors,
            by: \.seriesId
        ).mapValues { rows in rows.compactMap { authorNamesById[$0.authorId] } }

        let seriesCollections =
            try SeriesCollectionRecord
            .filter(seriesIds.contains(SeriesCollectionRecord.Columns.seriesId))
            .fetchAll(db)
        let collectionNamesById = Dictionary(
            uniqueKeysWithValues: try CollectionRecord.fetchAll(db).compactMap { collection in
                collection.id.map { ($0, collection.name) }
            }
        )
        let collectionNamesBySeriesId = Dictionary(
            grouping: seriesCollections,
            by: \.seriesId
        ).mapValues { rows in rows.compactMap { collectionNamesById[$0.collectionId] } }

        let trackerLinks =
            try SeriesTrackerRecord
            .filter(seriesIds.contains(SeriesTrackerRecord.Columns.seriesId))
            .fetchAll(db)
        let trackerLinksBySeriesId = Dictionary(grouping: trackerLinks, by: \.seriesId)

        let originsBySeriesId = Dictionary(grouping: origins, by: \.seriesId)

        var backup = LibraryBackup()
        backup.exportedByAppVersion = Bundle.main.appVersion
        backup.exportedDate = Int64(Date.now.timeIntervalSince1970)
        backup.series = series.compactMap { row in
            guard let seriesId = row.id else { return nil }

            var entry = LibraryBackup.SeriesEntry()
            entry.preferredTitle = titlesBySeriesId[seriesId.rawValue] ?? ""
            entry.status = row.status.rawValue
            entry.addedDate = Int64(row.addedDate.timeIntervalSince1970)
            entry.lastReadDate = Int64(row.lastReadDate.timeIntervalSince1970)
            entry.orientation = row.orientation.rawValue
            entry.showAllChapters = row.showAllChapters
            entry.showHalfChapters = row.showHalfChapters
            if let catalogId = row.catalogId {
                entry.catalogID = catalogId
            }

            entry.origins = (originsBySeriesId[seriesId] ?? []).compactMap { origin in
                guard let originId = origin.id,
                    let sourceId = origin.sourceId,
                    let sourceSlug = sourceSlugsById[sourceId]
                else { return nil }

                var originEntry = LibraryBackup.SeriesEntry.OriginEntry()
                originEntry.sourceSlug = sourceSlug
                originEntry.seriesSlug = origin.slug
                originEntry.priority = Int32(origin.priority)
                originEntry.chapters = (chaptersByOriginId[originId] ?? []).map { chapter in
                    var chapterEntry = LibraryBackup.SeriesEntry.ChapterEntry()
                    chapterEntry.number = chapter.number
                    chapterEntry.slug = chapter.slug
                    chapterEntry.title = chapter.title
                    chapterEntry.url = chapter.url.absoluteString
                    chapterEntry.language = chapter.language.rawValue
                    chapterEntry.scanlator = scanlatorNamesById[chapter.scanlatorId] ?? ""
                    chapterEntry.publishedDate = Int64(chapter.publishedDate.timeIntervalSince1970)
                    chapterEntry.addedDate = Int64(chapter.addedDate.timeIntervalSince1970)
                    chapterEntry.progress = chapter.progress
                    if let lastReadDate = chapter.lastReadDate {
                        chapterEntry.lastReadDate = Int64(lastReadDate.timeIntervalSince1970)
                    }
                    return chapterEntry
                }
                return originEntry
            }

            entry.tags = tagNamesBySeriesId[seriesId] ?? []
            entry.authors = authorNamesBySeriesId[seriesId] ?? []
            entry.collections = collectionNamesBySeriesId[seriesId] ?? []

            entry.trackerLinks = (trackerLinksBySeriesId[seriesId] ?? []).map { link in
                var trackerLink = LibraryBackup.SeriesEntry.TrackerLink()
                trackerLink.tracker = link.tracker.rawValue
                trackerLink.remoteID = link.remoteId
                if let remoteEntryId = link.remoteEntryId {
                    trackerLink.remoteEntryID = remoteEntryId
                }
                trackerLink.remoteTitle = link.remoteTitle
                if let remoteStatus = link.remoteStatus {
                    trackerLink.remoteStatus = remoteStatus.rawValue
                }
                trackerLink.remoteProgress = Int32(link.remoteProgress)
                if let remoteScore = link.remoteScore {
                    trackerLink.remoteScore = Int32(remoteScore)
                }
                if let totalChapters = link.totalChapters {
                    trackerLink.totalChapters = Int32(totalChapters)
                }
                return trackerLink
            }

            return entry
        }

        return backup
    }
}

extension Bundle {
    fileprivate var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

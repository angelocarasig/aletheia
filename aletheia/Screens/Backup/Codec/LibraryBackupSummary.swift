//
//  LibraryBackupSummary.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

struct LibraryBackupSummary: Equatable {
    let seriesCount: Int
    let chapterCount: Int
    let tagCount: Int
    let authorCount: Int
    let collectionCount: Int
    let trackerLinkCount: Int

    // distinct by name - the portable identity the schema itself uses
    init(decoding backup: LibraryBackup) {
        seriesCount = backup.series.count
        chapterCount = backup.series.reduce(0) { total, series in
            total + series.origins.reduce(0) { $0 + $1.chapters.count }
        }
        tagCount = Set(backup.series.flatMap(\.tags)).count
        authorCount = Set(backup.series.flatMap(\.authors)).count
        collectionCount = Set(backup.series.flatMap(\.collections)).count
        trackerLinkCount = backup.series.reduce(0) { $0 + $1.trackerLinks.count }
    }

    init(
        seriesCount: Int,
        chapterCount: Int,
        tagCount: Int,
        authorCount: Int,
        collectionCount: Int,
        trackerLinkCount: Int
    ) {
        self.seriesCount = seriesCount
        self.chapterCount = chapterCount
        self.tagCount = tagCount
        self.authorCount = authorCount
        self.collectionCount = collectionCount
        self.trackerLinkCount = trackerLinkCount
    }
}

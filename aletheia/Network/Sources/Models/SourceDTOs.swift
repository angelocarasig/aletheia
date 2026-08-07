//
//  SourceDTOs.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import CoreGraphics

/// lightweight search result.
struct SeriesStub: Sendable, Hashable {
    let slug: String
    let title: String
    let cover: URL?
    let latestChapterNumber: Double?
    let latestChapterDate: Date?
}

/// full series metadata from a source.
struct SeriesDetail: Sendable {
    let slug: String
    let title: String
    let altTitles: [String]
    let synopsis: String
    let url: URL
    let classification: Classification
    let publication: Publication
    let covers: [URL]
    let tags: [String]
    let authors: [String]
}

/// a chapter entry in a series' chapter list.
struct ChapterEntry: Sendable {
    let slug: String
    let title: String
    let number: Double
    let language: LanguageCode
    let scanlator: String
    let url: URL
    let publishedDate: Date
}

/// a single page image within a chapter's content.
struct PageURL: Sendable {
    let index: Int
    let url: URL
    let size: PageSize?

    init(index: Int, url: URL, size: PageSize? = nil) {
        self.index = index
        self.url = url
        self.size = size
    }
}

// a hint, never ground truth - only the bytes decide. it exists so a reader can
// lay a page out before its image arrives, and no source is ever required to
// make an extra request to fill it in.
//
// dimensions describe the file `url` serves, after any EXIF orientation. a
// quality variant is a different file with different dimensions, so a hint
// never transfers between them
struct PageSize: Sendable, Equatable {
    let width: Int
    let height: Int
    let exactness: Exactness

    // scraped attributes are routinely normalised for a site's own viewer -
    // Webtoons stamps width="700" with a float height - so the ratio survives
    // where the pixels do not. only `.exact` may drive splitting or texture
    // decisions; `.ratio` is good for layout and nothing else
    enum Exactness: Sendable {
        case exact
        case ratio
    }

    var aspectRatio: CGFloat? {
        guard width > 0, height > 0 else { return nil }
        return CGFloat(height) / CGFloat(width)
    }
}

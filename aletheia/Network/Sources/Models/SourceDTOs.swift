//
//  SourceDTOs.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import CoreGraphics
import Foundation

struct SeriesStub: Sendable, Hashable {
    let slug: String
    let title: String
    let cover: URL?

    /// pornographic, as this source draws that line - never comparable across sources
    /// (MangaDex's `pornographic` tier != WeebCentral's wider flag). a claim, not a
    /// guess: `true` only when the source knows, `false` only when it can guarantee.
    /// see docs/features/adult-content.md
    let adult: Bool

    init(slug: String, title: String, cover: URL?, adult: Bool = false) {
        self.slug = slug
        self.title = title
        self.cover = cover
        self.adult = adult
    }
}

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

struct ChapterEntry: Sendable {
    let slug: String
    let title: String
    let number: Double
    let language: LanguageCode
    let scanlator: String
    let url: URL
    let publishedDate: Date
}

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

// a hint, never ground truth - only the bytes decide. describes the file `url`
// serves after any EXIF orientation; a quality variant is a different file with
// different dimensions, so a hint never transfers between them
struct PageSize: Sendable, Equatable {
    let width: Int
    let height: Int
    let exactness: Exactness

    // scraped attributes are routinely normalised for a site's own viewer - Webtoons
    // stamps width="700" with a float height - so the ratio survives where the pixels
    // do not. only `.exact` may drive splitting or texture decisions
    enum Exactness: Sendable {
        case exact
        case ratio
    }

    var aspectRatio: CGFloat? {
        guard width > 0, height > 0 else { return nil }
        return CGFloat(height) / CGFloat(width)
    }
}

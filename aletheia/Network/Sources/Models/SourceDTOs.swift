//
//  SourceDTOs.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

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
}

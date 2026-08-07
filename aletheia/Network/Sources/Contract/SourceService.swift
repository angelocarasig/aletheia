//
//  SourceService.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

protocol SourceService: Sendable {
    var descriptor: SourceDescriptor { get }

    var presets: [SourcePreset] { get }

    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub>

    func details(seriesSlug: String) async throws -> SeriesDetail

    // an empty list means the series has none. throwing is the only way to say
    // nothing at all, and the only answer that leaves the stored list unknown.
    // a source that can check cheaply whether anything changed conforms to
    // RevalidatingSource as well
    func chapters(seriesSlug: String) async throws -> [ChapterEntry]

    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL]
}

extension SourceService {
    // a source with nothing to show on its home screen is the normal case, so
    // it is the default rather than something every source has to write out
    var presets: [SourcePreset] { [] }
}

typealias Source = any SourceService

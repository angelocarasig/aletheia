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

    // nil means the source knows nothing changed and the stored list still
    // stands - `have` is what the caller already holds, so a source that can
    // check cheaply can skip refetching the rest
    func chapters(seriesSlug: String, have: Int) async throws -> [ChapterEntry]?

    func content(seriesSlug:String, chapterSlug: String) async throws -> [PageURL]
}

extension SourceService {
    var presets: [SourcePreset] { [] }

    func chapters(seriesSlug: String) async throws -> [ChapterEntry]? {
        try await chapters(seriesSlug: seriesSlug, have: 0)
    }
}

typealias Source = any SourceService

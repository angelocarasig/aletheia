//
//  DetailsComposer+Series.swift
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
    final class Series: DetailsApplying, DetailsWriting {
        private(set) var title = ""
        private(set) var cover: URL?
        private(set) var referer: URL?
        private(set) var synopsis: AttributedString?
        private(set) var authors: [String] = []
        private(set) var tags: [String] = []
        private(set) var classification: Classification?
        private(set) var publication: Publication?
        private(set) var readCount = 0
        private(set) var totalCount = 0
        private(set) var lastReadDate: Date?
        private(set) var metadataFetchedDate: Date?
        private(set) var chaptersFetchedDate: Date?

        private(set) var covers: [Cover] = []
        private(set) var titles: [Title] = []
        private(set) var synopses: [Synopsis] = []
        private(set) var choices: [Metadata] = []

        private(set) var writing: Preference?

        var saving: Bool { writing != nil }
        private(set) var failure: Failure?

        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        // a cover swapping from its remote url to its downloaded file changes
        // the kingfisher cache key, replaying the fade - first answer wins for
        // the life of this screen, the local file is picked up next open instead
        @ObservationIgnored private var resolved: [String: URL] = [:]

        private let registry: Compositor.Registry
        private let assets: Compositor.Assets
        private let database: DatabaseClient

        init(
            registry: Compositor.Registry,
            assets: Compositor.Assets,
            database: DatabaseClient,
            stub: SeriesStub?,
            referer: URL?
        ) {
            self.registry = registry
            self.assets = assets
            self.database = database

            // referer matters even here: read outside the skeleton gate, and a
            // cover request without it is a 403 on any cloudflare-fronted source
            self.title = stub?.title ?? ""
            self.cover = stub?.cover
            self.referer = referer
        }

        func apply(_ stored: Stored) {
            seriesId = stored.series.id

            let entry = stored.entry

            title = entry.title
            cover = artwork(entry.cover, path: entry.path)
            synopsis = entry.synopsis?.isEmpty == false ? entry.synopsis?.toAttributed() : nil
            authors = Self.split(entry.authors)
            classification = entry.classification
            publication = entry.publication
            readCount = entry.readChapterCount
            totalCount = entry.totalChapterCount
            lastReadDate = entry.lastReadDate > .distantPast ? entry.lastReadDate : nil

            let sorted = Self.split(entry.tags)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if tags != sorted { tags = sorted }

            // taken from the stored row rather than looked up live, so it
            // outlives the source being uninstalled
            referer = stored.origins.first?.sourceReferer

            let primary =
                stored.origins.first { $0.installed && !$0.disconnected && !$0.disabled }
                ?? stored.origins.first
            metadataFetchedDate = primary?.metadataFetchedDate
            chaptersFetchedDate = primary?.chaptersFetchedDate

            let mappedTitles = stored.titles.map { row in
                Title(
                    id: row.id,
                    value: row.value,
                    sourceName: name(source: row.sourceName, tracker: row.tracker),
                    sourceIcon: glyph(slug: row.sourceSlug, tracker: row.tracker),
                    isPreferred: row.isPreferred
                )
            }
            if titles != mappedTitles { titles = mappedTitles }

            let mappedCovers = stored.covers.map { row in
                Cover(
                    id: row.id,
                    url: row.url,
                    local: artwork(nil, path: row.path),
                    sourceName: name(source: row.sourceName, tracker: row.tracker),
                    sourceIcon: glyph(slug: row.sourceSlug, tracker: row.tracker),
                    isPreferred: row.isPreferred
                )
            }
            if covers != mappedCovers { covers = mappedCovers }

            let mappedSynopses = stored.suppliers.compactMap { row -> Synopsis? in
                guard !row.synopsis.isEmpty else { return nil }

                return Synopsis(
                    id: row.id,
                    sourceName: name(source: row.sourceName, tracker: row.tracker),
                    sourceIcon: glyph(slug: row.sourceSlug, tracker: row.tracker),
                    text: row.synopsis,
                    isPreferred: row.isSynopsis
                )
            }
            if synopses != mappedSynopses { synopses = mappedSynopses }

            let mappedChoices = stored.suppliers.map { row in
                Metadata(
                    id: row.id,
                    sourceName: name(source: row.sourceName, tracker: row.tracker),
                    sourceIcon: glyph(slug: row.sourceSlug, tracker: row.tracker),
                    classification: row.classification,
                    publication: row.publication,
                    isClassification: row.isClassification,
                    isPublication: row.isPublication,
                    detached: row.detached
                )
            }
            if choices != mappedChoices { choices = mappedChoices }
        }

        private func icon(_ slug: String?) -> ImageResource? {
            slug.flatMap { registry.source(slug: $0) }?.descriptor.icon
        }

        // no slug fallback: name and slug come off the same joined source row,
        // so either both arrive or neither does
        private func name(source: String?, tracker: Tracker?) -> String? {
            tracker?.name ?? source
        }

        private func glyph(slug: String?, tracker: Tracker?) -> ImageResource? {
            if let tracker { return ImageResource(name: tracker.icon, bundle: .main) }
            return icon(slug)
        }

        func clear() {
            failure = nil
        }

        func artwork(_ remote: URL?, path: String?) -> URL? {
            guard let remote else { return assets.local(for: path) }
            if let seen = resolved[remote.absoluteString] { return seen }

            let url = assets.local(for: path) ?? remote
            resolved[remote.absoluteString] = url
            return url
        }

        func prefer(cover id: Int64?) async {
            await write(.cover(id))
        }

        func prefer(title id: Int64?) async {
            await write(.title(id))
        }

        func prefer(synopsis metadataId: Int64?) async {
            await write(.synopsis(metadataId))
        }

        func prefer(classification metadataId: Int64?) async {
            await write(.classification(metadataId))
        }

        func prefer(publication metadataId: Int64?) async {
            await write(.publication(metadataId))
        }

        private func write(_ preference: Preference) async {
            guard let seriesId else { return }

            writing = preference
            defer { writing = nil }

            do {
                try await database.writer.write { db in
                    _ =
                        try SeriesRecord
                        .filter(key: seriesId.rawValue)
                        .updateAll(db, preference.column.set(to: preference.id))
                }
            } catch {
                failure = Failure(error, fallback: preference.fallback)
            }
        }
    }
}

extension DetailsComposer.Series {
    // group_concat joins with ", " and yields null rather than an empty string
    nonisolated static func split(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.components(separatedBy: ", ").filter { !$0.isEmpty }
    }
}

// the pools a preference picks from. every one is add-only, so a source going
// away never removes an option the reader has already chosen
extension DetailsComposer.Series {
    struct Cover: Identifiable, Hashable {
        let id: Int64
        // the remote url stays the identity and what Share offers - handing out
        // a file inside the app group container is a different action entirely
        let url: URL
        let local: URL?
        let sourceName: String?
        // qualified because Kingfisher declares an ImageResource of its own
        let sourceIcon: SwiftUI.ImageResource?
        let isPreferred: Bool

        var artwork: URL { local ?? url }
    }

    struct Title: Identifiable, Hashable {
        let id: Int64
        let value: String
        let sourceName: String?
        let sourceIcon: ImageResource?
        let isPreferred: Bool
    }

    struct Synopsis: Identifiable, Hashable {
        // the metadata row it came from, not the series or the origin
        let id: Int64
        let sourceName: String?
        let sourceIcon: ImageResource?
        let text: String
        let isPreferred: Bool
    }

    // the row is the pinning unit - a supplier cannot be pinned for one field
    // and absent for the other
    struct Metadata: Identifiable, Hashable {
        let id: Int64
        let sourceName: String?
        let sourceIcon: ImageResource?
        let classification: Classification
        let publication: Publication
        let isClassification: Bool
        let isPublication: Bool
        // no supplier left, so it can only ever be reached by an explicit pin
        let detached: Bool
    }
}

// the id is what a picker spins for the row that was tapped, not the whole
// list; nil is the "automatic" row, a row like any other
extension DetailsComposer.Series {
    enum Preference: Hashable {
        case cover(Int64?)
        case title(Int64?)
        case synopsis(Int64?)
        // one pin each rather than one for both: the best publication authority
        // is often the worst classification one, and a shared pin would force
        // both answers from the same supplier
        case classification(Int64?)
        case publication(Int64?)

        var column: Column {
            switch self {
            case .cover: SeriesRecord.Columns.preferredCoverId
            case .title: SeriesRecord.Columns.preferredTitleId
            case .synopsis: SeriesRecord.Columns.preferredSynopsisId
            case .classification: SeriesRecord.Columns.preferredClassificationId
            case .publication: SeriesRecord.Columns.preferredPublicationId
            }
        }

        var id: Int64? {
            switch self {
            case .cover(let id), .title(let id), .synopsis(let id),
                .classification(let id), .publication(let id):
                id
            }
        }

        var fallback: String {
            switch self {
            case .cover: "Couldn't Set Cover"
            case .title: "Couldn't Set Title"
            case .synopsis, .classification, .publication: "Couldn't Save Preference"
            }
        }
    }
}

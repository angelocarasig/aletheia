//
//  DetailsComposer+Series.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import Foundation
import GRDB
import Tagged
import Observation
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

        // every alternative a source has offered, not just the one on show.
        // add-only, so a pick can never be taken away by a later fetch
        private(set) var covers: [Cover] = []
        private(set) var titles: [Title] = []
        private(set) var synopses: [Synopsis] = []
        private(set) var choices: [Metadata] = []

        // which preference is committing, nil when none is. a value rather
        // than a flag because these are all picked from a list, and a flag
        // dims every row in it for a write that belongs to one
        private(set) var writing: Preference?

        // from DetailsWriting
        var saving: Bool { writing != nil }
        private(set) var failure: Failure?

        @ObservationIgnored private var seriesId: SeriesRecord.ID?

        // a cover swapping from its remote url to its downloaded file changes
        // the kingfisher cache key, which replays the fade. first answer wins
        // for the life of this screen, so the local file is picked up on the
        // next open instead
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

            // what the search result already knew, held until the first bundle
            // overwrites it. referer is the one that matters: it is read
            // outside the skeleton gate, and a cover request without it is a
            // 403 on any cloudflare-fronted source
            self.title = stub?.title ?? ""
            self.cover = stub?.cover
            self.referer = referer
        }

        // from DetailsApplying
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

            // sources return tags in their own order, so sort for display
            let sorted = Self.split(entry.tags)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if tags != sorted { tags = sorted }

            // whichever origin heads the list supplies the displayed cover, so
            // its referer is the one image requests have to carry - taken from
            // the stored row, so it outlives the source being uninstalled
            referer = stored.origins.first?.sourceReferer

            let primary = stored.origins.first { $0.installed && !$0.disconnected && !$0.disabled }
                ?? stored.origins.first
            metadataFetchedDate = primary?.metadataFetchedDate
            chaptersFetchedDate = primary?.chaptersFetchedDate

            let mappedTitles = stored.titles.map { row in
                Title(
                    id: row.id,
                    value: row.value,
                    sourceName: row.sourceName,
                    sourceIcon: icon(row.sourceSlug),
                    isPreferred: row.isPreferred
                )
            }
            if titles != mappedTitles { titles = mappedTitles }

            let mappedCovers = stored.covers.map { row in
                Cover(
                    id: row.id,
                    url: row.url,
                    local: artwork(nil, path: row.path),
                    sourceName: row.sourceName,
                    sourceIcon: icon(row.sourceSlug),
                    isPreferred: row.isPreferred
                )
            }
            if covers != mappedCovers { covers = mappedCovers }

            // an origin with no synopsis has nothing to offer, so it is not a
            // choice
            let mappedSynopses = stored.origins.compactMap { row -> Synopsis? in
                guard !row.synopsis.isEmpty else { return nil }

                return Synopsis(
                    id: row.id,
                    sourceName: row.sourceName ?? row.sourceSlug,
                    sourceIcon: icon(row.sourceSlug),
                    text: row.synopsis,
                    isPreferred: row.isSynopsis
                )
            }
            if synopses != mappedSynopses { synopses = mappedSynopses }

            let mappedChoices = stored.origins.map { row in
                Metadata(
                    id: row.id,
                    sourceName: row.sourceName ?? row.sourceSlug,
                    sourceIcon: icon(row.sourceSlug),
                    classification: row.classification,
                    publication: row.publication,
                    isPreferred: row.isMetadata
                )
            }
            if choices != mappedChoices { choices = mappedChoices }
        }

        private func icon(_ slug: String?) -> ImageResource? {
            slug.flatMap { registry.source(slug: $0) }?.descriptor.icon
        }

        // from DetailsWriting
        func clear() {
            failure = nil
        }

        // which url to draw a cover from: the downloaded file if there is one,
        // the remote url otherwise, and the file alone when there is no remote
        // to fall back on. memoised in `resolved`, which is where the reason is
        func artwork(_ remote: URL?, path: String?) -> URL? {
            guard let remote else { return assets.local(for: path) }
            if let seen = resolved[remote.absoluteString] { return seen }

            let url = assets.local(for: path) ?? remote
            resolved[remote.absoluteString] = url
            return url
        }

        // which artwork the series shows
        func prefer(cover id: Int64?) async {
            await write(.cover(id))
        }

        // which of the pooled titles the series is listed under
        func prefer(title id: Int64?) async {
            await write(.title(id))
        }

        // whose description is shown, picked by origin rather than by row - a
        // source writes one synopsis per series, so the origin names it
        func prefer(synopsis originId: Int64?) async {
            await write(.synopsis(originId))
        }

        // whose content rating and publication status are shown, same reasoning
        func prefer(metadata originId: Int64?) async {
            await write(.metadata(originId))
        }

        // the one write behind all four. nil clears the pick and hands the
        // choice back to origin priority, which always resolves to something,
        // so clearing can never leave the screen with nothing to show
        private func write(_ preference: Preference) async {
            guard let seriesId else { return }

            writing = preference
            defer { writing = nil }

            do {
                try await database.writer.write { db in
                    _ = try SeriesRecord
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
        // the remote url stays the identity, and stays what Share offers -
        // handing out a file inside the app group container is a different
        // action entirely
        let url: URL
        let local: URL?
        let sourceName: String?
        // nil when the contributing source is no longer installed. qualified
        // because Kingfisher declares an ImageResource of its own
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
        // the origin it came from, not the series
        let id: Int64
        let sourceName: String?
        let sourceIcon: ImageResource?
        let text: String
        let isPreferred: Bool
    }

    struct Metadata: Identifiable, Hashable {
        let id: Int64
        let sourceName: String?
        let sourceIcon: ImageResource?
        let classification: Classification
        let publication: Publication
        let isPreferred: Bool
    }
}

// which preference is being written, and to what. the id is what a picker
// needs to spin the row that was tapped rather than the whole list, and nil is
// the "automatic" row, which is a row like any other
extension DetailsComposer.Series {
    enum Preference: Hashable {
        case cover(Int64?)
        case title(Int64?)
        case synopsis(Int64?)
        case metadata(Int64?)

        var column: Column {
            switch self {
            case .cover: SeriesRecord.Columns.preferredCoverId
            case .title: SeriesRecord.Columns.preferredTitleId
            case .synopsis: SeriesRecord.Columns.preferredSynopsisOriginId
            case .metadata: SeriesRecord.Columns.preferredMetadataOriginId
            }
        }

        var id: Int64? {
            switch self {
            case .cover(let id), .title(let id), .synopsis(let id), .metadata(let id): id
            }
        }

        var fallback: String {
            switch self {
            case .cover: "Couldn't Set Cover"
            case .title: "Couldn't Set Title"
            case .synopsis, .metadata: "Couldn't Save Preference"
            }
        }
    }
}

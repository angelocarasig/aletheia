//
//  AtsumaruSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// two backends behind one host. search goes to a typesense collection proxied
// unauthenticated at /collections, everything else to a hono rpc api at /api.
// no credential, no renderer, no signing - see docs/sources/atsumaru.md
struct AtsumaruSource: SourceService {
    let network: NetworkConfiguration

    private static let cdn = URL(string: "https://cdn.atsu.moe")!
    private static let window = 30

    // the field set the site's own search sends, weights included. queried
    // fields are ordered most to least authoritative
    private static let queryFields = "title,englishTitle,otherNames,authors,acronyms"
    private static let queryWeights = "4,3,2,1,1"

    let descriptor = SourceDescriptor(
        slug: "atsumaru",
        name: "Atsumaru",
        description: "Read, track and download thousands of Manga, Manhwa and Manhua series all Ad-Free on Atsumaru.",
        icon: .atsumaru,
        // nothing in the api carries a language: not the manga document, not the
        // chapter list, not the page payload. the catalogue is an english
        // scanlation aggregator, so this is asserted rather than read
        languages: [.english],
        baseURL: URL(string: "https://atsu.moe")!,
        referer: URL(string: "https://atsu.moe")!,
        supportedFilters: [
            .multiSelect(
                id: "genreIds",
                name: "Genres",
                options: [
                    .init(id: "39", name: "Action"),
                    .init(id: "46", name: "Adult", sensitivity: .suggestive),
                    .init(id: "37", name: "Adventure"),
                    .init(id: "180", name: "Boys Love"),
                    .init(id: "6", name: "Comedy"),
                    .init(id: "31", name: "Drama"),
                    .init(id: "36", name: "Fantasy"),
                    .init(id: "4", name: "Girls Love"),
                    .init(id: "10", name: "Hentai", sensitivity: .adult),
                    .init(id: "45", name: "Historical"),
                    .init(id: "44", name: "Horror"),
                    .init(id: "29", name: "Martial Arts"),
                    .init(id: "32", name: "Mystery"),
                    .init(id: "18", name: "Psychological"),
                    .init(id: "9", name: "Romance"),
                    .init(id: "1", name: "Sci-Fi"),
                    .init(id: "7", name: "Slice of Life"),
                    .init(id: "41", name: "Smut", sensitivity: .suggestive),
                    .init(id: "22", name: "Supernatural"),
                    .init(id: "19", name: "Thriller"),
                    .init(id: "5", name: "Tragedy")
                ],
                canExclude: true
            ),
            // their own spelling, kept as the id because that is what the filter
            // sends. only the label is corrected
            .multiSelect(
                id: "type",
                name: "Type",
                options: [
                    .init(id: "Manga", name: "Manga"),
                    .init(id: "Manwha", name: "Manhwa"),
                    .init(id: "Manhua", name: "Manhua"),
                    .init(id: "OEL", name: "OEL")
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "status",
                name: "Status",
                options: [
                    .init(id: "Ongoing", name: "Ongoing"),
                    .init(id: "Completed", name: "Completed"),
                    .init(id: "Hiatus", name: "Hiatus"),
                    .init(id: "Canceled", name: "Cancelled")
                ],
                canExclude: false
            ),
            // 2408 of them, so they ship as a bundled resource rather than as
            // literals here. see the Vocabulary extension below
            .multiSelect(
                id: "tagIds",
                name: "Tags",
                options: AtsumaruSource.tags,
                canExclude: true
            ),
            .multiSelect(
                id: "mbContentRating",
                name: "Content Rating",
                options: [
                    .init(id: "Safe", name: "Safe"),
                    .init(id: "Suggestive", name: "Suggestive"),
                    .init(id: "Erotica", name: "Erotica", sensitivity: .suggestive),
                    .init(id: "Pornographic", name: "Pornographic", sensitivity: .adult)
                ],
                canExclude: false
            ),
            .number(id: "year", name: "Year")
        ],
        // typesense takes direction in the sort expression itself, so each option
        // id is the whole `field:direction` and ascending goes unused
        supportedSort: .init(
            options: [
                .init(id: "", name: "Best match"),
                .init(id: "views:desc", name: "Popularity"),
                .init(id: "trending:desc", name: "Trending"),
                .init(id: "dateAdded:desc", name: "Recently added"),
                .init(id: "releaseDate:desc", name: "Release date"),
                .init(id: "mbRating:desc", name: "Top rated"),
                .init(id: "title:asc", name: "Title (A-Z)")
            ],
            defaultSort: ""
        )
    )

    var presets: [SourcePreset] {
        [
            .init(id: "new", name: "Recently Added", subtitle: "Newest to the catalogue", order: 0,
                  sort: .init(optionID: "dateAdded:desc")),
            // ranked by newest chapter, which no typesense field carries - served
            // by a home shelf endpoint instead, hence the route
            .init(id: "updated", name: "Recently Updated", subtitle: "Freshly released chapters", order: 1,
                  route: "recentlyUpdated"),
            .init(id: "trending", name: "Trending", subtitle: "Climbing right now", order: 2,
                  sort: .init(optionID: "trending:desc")),
            .init(id: "popular", name: "Popular", subtitle: "Most read on Atsumaru", order: 3,
                  sort: .init(optionID: "views:desc")),
            .init(id: "top", name: "Top Rated", subtitle: "Highest rated series", order: 4,
                  sort: .init(optionID: "mbRating:desc"))
        ]
    }
}

// MARK: - Vocabulary

extension AtsumaruSource {
    // a filter vocabulary too large to write out: 2408 tags, ~230kb of json.
    // bundled rather than fetched, which trades freshness for costing nothing at
    // runtime - and means the taxonomy only moves when we ship, so it can take
    // part in the descriptor's fingerprint honestly.
    //
    // the file is named for the source it belongs to; a second vocabulary would
    // be `atsumaru-<name>.json`. ordered by how many series carry each tag, so
    // the picker's default order is useful before Option carries a count
    static let tags: [SourceFilter.Option] = load("atsumaru-tags")

    // an unreadable vocabulary is an empty filter, never a crash: the rest of
    // the source is unaffected and search still works without it
    private static func load(_ resource: String) -> [SourceFilter.Option] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            AppLog.shared.log("vocabulary \(resource).json missing or unreadable", category: "source")
            return []
        }

        // their flag is one bit and drawn wide - gore and partial nudity carry it -
        // so it maps to the middle level, never the gate. this is the boundary:
        // their vocabulary stops here and ours starts
        return entries.map { .init(id: $0.id, name: $0.name, sensitivity: $0.sensitive ? .suggestive : .none) }
    }

    // group and count are carried in the file but dropped here - Option has
    // nowhere to put them yet, and the file should not have to be regenerated
    // when it does
    private struct Entry: Decodable {
        let id: String
        let name: String
        // the key is the file's, the property is ours. renaming 2408 entries to
        // match would buy nothing - the mapping is one line and stops the word
        // travelling any further
        let sensitive: Bool

        enum CodingKeys: String, CodingKey {
            case id, name
            case sensitive = "nsfw"
        }
    }
}

// MARK: - Search

extension AtsumaruSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        if query.route == "recentlyUpdated" {
            return try await recentlyUpdated(page: query.page)
        }

        let response: Documents<Stub> = try await fetch(
            Self.searchURL(query, sort: resolvedSort(for: query), fields: Self.stubFields, gateOpen: allowsAdult(for: query))
        )

        // typesense states the true total, so the last page is arithmetic rather
        // than the "a full page probably means more" guess every other source makes
        let seen = query.page * Self.window
        return SearchPage(
            items: response.hits.map { Self.stub(from: $0.document) },
            next: seen < response.found ? query.page + 1 : nil
        )
    }

    // series ranked by newest chapter, off the home shelf rather than typesense.
    // `adult` is deliberately never sent: a preset carries no filters so the gate
    // is always shut, and on this route omission IS the exclusion - adult=1 flips
    // the feed to adult-only, not mixed, so there is nothing between to ask for.
    // the shelf also mixes in the site's web novels, which the manga collection
    // does not hold and content() could not read - dropped before mapping
    private func recentlyUpdated(page: Int) async throws -> SearchPage<SeriesStub> {
        let response: HomeShelf = try await fetch(Self.api("home2/recentlyUpdated", [
            .init(name: "offset", value: String(max(0, page - 1) * Self.window)),
            .init(name: "limit", value: String(Self.window))
        ]))

        let comics = response.items.filter { $0.medium == "Comic" }
        return SearchPage(
            items: comics.map { item in
                SeriesStub(
                    slug: item.id,
                    title: item.title,
                    cover: Self.poster(item.mediumImage ?? item.image),
                    adult: item.isAdult ?? false
                )
            },
            // next is judged on the raw window, not the trimmed one - a page of
            // mostly novels still means the feed continues
            next: response.items.count == Self.window ? page + 1 : nil
        )
    }

    // rung 1: mbContentRating carries the four tiers our line is drawn in, so the
    // request never enters into it. `isAdult` is the fallback for the ~292 titles
    // mangabaka has never rated - the same precedence classification() uses, and
    // it is why 133 unrated-but-flagged titles the gate lets past still blur
    private static func stub(from document: Stub) -> SeriesStub {
        SeriesStub(
            slug: document.id,
            title: document.title,
            cover: poster(document.posterMedium ?? document.poster),
            adult: document.mbContentRating.map { $0 == pornographic } ?? (document.isAdult == true)
        )
    }
}

// MARK: - Details

extension AtsumaruSource {
    // one request: the search index holds the whole document, so filtering it to
    // a single id is cheaper than the two /api calls the website makes
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let response: Documents<Detail> = try await fetch(
            Self.documentURL(id: seriesSlug)
        )
        // the index answered but has no such id - a series pulled since the
        // search result was rendered looks exactly like this
        guard let document = response.hits.first?.document else {
            throw URLError(.badServerResponse)
        }

        return SeriesDetail(
            slug: document.id,
            title: document.title,
            altTitles: document.otherNames ?? [],
            synopsis: document.synopsis ?? "",
            url: descriptor.baseURL
                .appendingPathComponent("manga")
                .appendingPathComponent(document.id),
            classification: Self.classification(document),
            publication: Self.publication(document.status),
            // quality descending, because that is the order the pool is walked
            // in when one turns out to be gone - covers are inserted in this
            // order and the promotion takes the first survivor by id.
            //
            // details used to return the full-size alone, which is the variant
            // that goes missing from their cdn - so a series browsed with a
            // working cover was added to the library with a dead one. it also
            // broke preferredCoverId's first tier, which matches against the
            // SEARCH result's url: that url could never be in a pool built from
            // a field search does not use
            covers: [Self.poster(document.poster), Self.poster(document.posterMedium)]
                .compactMap { $0 },
            tags: document.tags ?? [],
            authors: document.authors ?? []
        )
    }

    // mbContentRating comes from mangabaka and is the richer signal; isAdult is
    // the fallback for a series that has never been rated
    private static func classification(_ document: Detail) -> Classification {
        switch document.mbContentRating {
        case "Safe": .Safe
        case "Suggestive": .Suggestive
        case "Erotica", "Pornographic": .Explicit
        default: document.isAdult == true ? .Explicit : .Unknown
        }
    }

    private static func publication(_ status: String?) -> Publication {
        switch status {
        case "Ongoing": .Ongoing
        case "Completed": .Completed
        case "Hiatus": .Hiatus
        case "Canceled": .Cancelled
        default: .Unknown
        }
    }
}

// MARK: - Chapters

extension AtsumaruSource {
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        // the chapter list names its scanlation group by id alone, and the names
        // live on a different endpoint. both are needed for one entry
        async let listing: ChapterList = fetch(Self.api("manga/allChapters", [
            .init(name: "mangaId", value: seriesSlug)
        ]))
        async let page: MangaPage = fetch(Self.api("manga/page", [
            .init(name: "id", value: seriesSlug)
        ]))

        let (chapters, scanlators) = try await (listing.chapters, page.mangaPage.scanlators)
        let names = Dictionary(
            scanlators.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        return chapters.map { chapter in
            ChapterEntry(
                slug: chapter.id,
                title: chapter.title ?? "",
                number: chapter.number ?? 0,
                language: .english,
                // an unnamed group still needs a stable key: this is what the
                // scanlator priority rows hang off, so it cannot vary per fetch
                scanlator: chapter.scanlationMangaId.flatMap { names[$0] } ?? descriptor.name,
                url: descriptor.baseURL
                    .appendingPathComponent("manga")
                    .appendingPathComponent(seriesSlug)
                    .appendingPathComponent(chapter.id),
                publishedDate: chapter.createdAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                    ?? .distantPast
            )
        }
    }
}

// MARK: - Content

extension AtsumaruSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        let response: ReadChapter = try await fetch(Self.api("read/chapter", [
            .init(name: "mangaId", value: seriesSlug),
            .init(name: "chapterId", value: chapterSlug)
        ]))

        return response.readChapter.pages.compactMap { page in
            guard let url = Self.asset(page.image) else { return nil }
            return PageURL(
                index: page.number,
                url: url,
                // stated by the api for every page, so a chapter here never
                // estimates a height - see features/page-dimensions.md
                size: page.width.flatMap { width in
                    page.height.map { PageSize(width: width, height: $0, exactness: .exact) }
                }
            )
        }
    }
}

// MARK: - Requests

private extension AtsumaruSource {
    func fetch<Model: Decodable>(_ url: URL) async throws -> Model {
        try await network.get(url: url, headers: ["Referer": descriptor.referer.absoluteString])
    }

    static func api(_ path: String, _ items: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: URL(string: "https://atsu.moe/api")!.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    static func collection(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: URL(string: "https://atsu.moe/collections/manga/documents/search")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items
        return components.url!
    }

    static let stubFields = "id,title,poster,posterSmall,posterMedium,mbContentRating,isAdult"
    static let pornographic = "Pornographic"
    // posterMedium is requested here for the same reason search asks for it: the
    // full-size poster is the variant that goes missing from their CDN, and it
    // was the only one details returned - so a series browsed with a working
    // cover was added to the library with a dead one
    static let detailFields = "id,title,otherNames,synopsis,poster,posterMedium,status,isAdult,mbContentRating,tags,authors"

    static func documentURL(id: String) -> URL {
        collection([
            .init(name: "q", value: "*"),
            .init(name: "query_by", value: "title"),
            .init(name: "filter_by", value: "id:=\(quoted(id))"),
            .init(name: "include_fields", value: detailFields),
            .init(name: "per_page", value: "1")
        ])
    }

    static func searchURL(_ query: SearchQuery, sort: SortSelection?, fields: String, gateOpen: Bool) -> URL {
        var items: [URLQueryItem] = [
            // a blank search is a match-all rather than an error
            .init(name: "q", value: query.text?.isEmpty == false ? query.text! : "*"),
            .init(name: "query_by", value: queryFields),
            .init(name: "query_by_weights", value: queryWeights),
            .init(name: "include_fields", value: fields),
            .init(name: "per_page", value: String(window)),
            .init(name: "page", value: String(max(1, query.page)))
        ]

        if let sort = sort?.optionID, !sort.isEmpty {
            items.append(.init(name: "sort_by", value: sort))
        }

        var clauses = filters(query.filters)

        // typesense filters nothing it is not asked to, so an omitted clause is
        // the whole 19,723-title catalogue - 22% of it flagged adult. the gate
        // shut means excluding, never staying quiet.
        //
        // `!=` matches a missing value too, verified against the live index, so
        // the 292 titles mangabaka has never rated stay visible rather than
        // disappearing into a whitelist's blind spot
        if !gateOpen, !query.filters.contains(where: { $0.id == "mbContentRating" }) {
            clauses.append("mbContentRating:!=\(quoted(pornographic))")
        }

        if !clauses.isEmpty {
            items.append(.init(name: "filter_by", value: clauses.joined(separator: " && ")))
        }

        return collection(items)
    }

    // typesense filter syntax: `field:=value` includes, `field:!=[a,b]` excludes.
    // each included id is its own clause so they AND - one `:=[a,b]` would OR
    // them, which is not what picking two genres means
    static func filters(_ selections: [FilterSelection]) -> [String] {
        selections.flatMap { selection -> [String] in
            switch selection {
            case let .multiSelect(id, included, excluded):
                var clauses = included.map { "\(id):=\(quoted($0))" }
                if !excluded.isEmpty {
                    clauses.append("\(id):!=[\(excluded.map(quoted).joined(separator: ","))]")
                }
                return clauses

            case let .select(id, optionID):
                return ["\(id):=\(quoted(optionID))"]

            case let .number(id, value):
                return ["\(id):=\(value)"]

            case let .text(id, value):
                return value.isEmpty ? [] : ["\(id):=\(quoted(value))"]
            }
        }
    }

    // backticks are typesense's own literal quoting, so an id containing a comma
    // or a space cannot split the clause it sits in
    static func quoted(_ value: String) -> String {
        "`\(value.replacingOccurrences(of: "`", with: ""))`"
    }

    // every image path is site-relative and 301s to the cdn. resolving it here
    // spares each one a redirect
    static func asset(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: path, relativeTo: cdn)?.absoluteURL
    }

    static func poster(_ path: String?) -> URL? {
        asset(path)
    }
}

// MARK: - Responses

private extension AtsumaruSource {
    struct Documents<Document: Decodable & Sendable>: Decodable, Sendable {
        let found: Int
        let hits: [Hit]

        struct Hit: Decodable, Sendable {
            let document: Document
        }
    }

    struct Stub: Decodable, Sendable {
        let id: String
        let title: String
        let poster: String?
        let posterSmall: String?
        let posterMedium: String?
        let mbContentRating: String?
        let isAdult: Bool?
    }

    struct HomeShelf: Decodable, Sendable {
        let items: [Item]

        struct Item: Decodable, Sendable {
            let id: String
            let title: String
            let image: String?
            let mediumImage: String?
            let isAdult: Bool?
            let medium: String?
        }
    }

    struct Detail: Decodable, Sendable {
        let id: String
        let title: String
        let otherNames: [String]?
        let synopsis: String?
        let poster: String?
        let posterMedium: String?
        let status: String?
        let isAdult: Bool?
        let mbContentRating: String?
        let tags: [String]?
        let authors: [String]?
    }

    struct ChapterList: Decodable, Sendable {
        let chapters: [Chapter]

        struct Chapter: Decodable, Sendable {
            let id: String
            let scanlationMangaId: String?
            let title: String?
            let number: Double?
            let createdAt: Double?
        }
    }

    struct MangaPage: Decodable, Sendable {
        let mangaPage: Page

        struct Page: Decodable, Sendable {
            let scanlators: [Scanlator]
        }

        struct Scanlator: Decodable, Sendable {
            let id: String
            let name: String
        }
    }

    struct ReadChapter: Decodable, Sendable {
        let readChapter: Chapter

        struct Chapter: Decodable, Sendable {
            let pages: [Page]
        }

        struct Page: Decodable, Sendable {
            let image: String?
            let number: Int
            let width: Int?
            let height: Int?
        }
    }
}

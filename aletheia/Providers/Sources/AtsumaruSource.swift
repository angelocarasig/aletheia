//
//  AtsumaruSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

struct AtsumaruSource: SourceService {
    let network: NetworkConfiguration

    private static let cdn = URL(string: "https://cdn.atsu.moe")!
    private static let window = 30
    // the shelf routes page themselves, 40 at a time, and take no size argument
    private static let shelfWindow = 40
    private static let shelfTypes = "Manga,Manwha,Manhua,OEL"

    static let novelMedium = "Novel"

    // the field set the site's own search sends, weights included. queried
    // fields are ordered most to least authoritative
    private static let queryFields = "title,englishTitle,otherNames,authors,acronyms"
    private static let queryWeights = "4,3,2,1,1"

    let descriptor = SourceDescriptor(
        slug: "atsumaru",
        name: "Atsumaru",
        description:
            "Read, track and download thousands of Manga, Manhwa and Manhua series all Ad-Free on Atsumaru.",
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
                    .init(id: "5", name: "Tragedy"),
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
                    .init(id: "OEL", name: "OEL"),
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
                    .init(id: "Canceled", name: "Cancelled"),
                ],
                canExclude: false
            ),
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
                    .init(id: "Pornographic", name: "Pornographic", sensitivity: .adult),
                ],
                canExclude: false
            ),
            .number(id: "year", name: "Year"),
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
                .init(id: "title:asc", name: "Title (A-Z)"),
            ],
            defaultSort: ""
        )
    )

    var presets: [SourcePreset] {
        [
            .init(
                id: "new", name: "Recently Added", subtitle: "Newest to the catalogue", order: 0,
                sort: .init(optionID: "dateAdded:desc")),
            .init(
                id: "updated", name: "Recently Updated", subtitle: "Freshly released chapters",
                order: 1,
                route: "recentlyUpdated"),
            .init(
                id: "trending", name: "Trending", subtitle: "Climbing right now", order: 2,
                sort: .init(optionID: "trending:desc")),
            .init(
                id: "popular", name: "Popular", subtitle: "Most read on Atsumaru", order: 3,
                sort: .init(optionID: "views:desc")),
            .init(
                id: "top", name: "Top Rated", subtitle: "Highest rated series", order: 4,
                sort: .init(optionID: "mbRating:desc")),
        ]
    }
}

// MARK: - Vocabulary

extension AtsumaruSource {
    // bundled rather than fetched: trades freshness for costing nothing at
    // runtime, and lets the taxonomy take part in the descriptor's fingerprint
    // honestly since it only moves when we ship
    static let tags: [SourceFilter.Option] = load("atsumaru-tags")

    // an unreadable vocabulary is an empty filter, never a crash: the rest of
    // the source is unaffected and search still works without it
    private static func load(_ resource: String) -> [SourceFilter.Option] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            AppLog.shared.log(
                "vocabulary \(resource).json missing or unreadable", level: .warning,
                category: "source")
            return []
        }

        // their flag is one bit and drawn wide - gore and partial nudity carry it -
        // so it maps to the middle level, never the gate. this is the boundary:
        // their vocabulary stops here and ours starts
        return entries.map {
            .init(id: $0.id, name: $0.name, sensitivity: $0.sensitive ? .suggestive : .none)
        }
    }

    private struct Entry: Decodable {
        let id: String
        let name: String
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
            Self.searchURL(
                query, sort: resolvedSort(for: query), fields: Self.stubFields,
                gateOpen: allowsAdult(for: query))
        )

        // typesense states the true total, so the last page is arithmetic rather
        // than the "a full page probably means more" guess every other source makes
        let seen = query.page * Self.window
        return SearchPage(
            items: response.hits.map { Self.stub(from: $0.document) },
            next: seen < response.found ? query.page + 1 : nil
        )
    }

    // series ranked by newest chapter, off a shelf endpoint rather than
    // typesense - no field in the collection carries chapter activity, so this
    // ordering cannot be a sort. every other implementation of this site landed
    // on the same split (mihon, two paperback extensions, a kotatsu fork), and
    // none exposes it as a sort option.
    //
    // `adult` is deliberately never sent: a preset carries no filters so the gate
    // is always shut, and on this route omission IS the exclusion - adult=1 flips
    // the feed to adult-only, not mixed, so there is nothing between to ask for.
    //
    // `types` is not optional despite looking it - omitted, the route answers
    // `{"items": []}` rather than everything. and it filters `type`, NOT
    // `medium`: the two are independent, and every novel sampled is typed Manga
    // or Manwha, so the whitelist does nothing about them. six of the forty on
    // page one were novels when this was last probed. mihon's extension sends
    // the same whitelist and ships the same leak
    private func recentlyUpdated(page: Int) async throws -> SearchPage<SeriesStub> {
        let response: HomeShelf = try await fetch(
            Self.api(
                "infinite/recentlyUpdated",
                [
                    // zero-based here, unlike everything else on this host
                    .init(name: "page", value: String(max(0, page - 1))),
                    .init(name: "types", value: Self.shelfTypes),
                ]))

        // excluding what cannot be read rather than including what can. the
        // search index has 132 documents carrying no `medium` at all which are
        // comics by every other measure, so an inclusive test drops real series
        // on a missing field - and a third medium arriving would be dropped too
        let comics = response.items.filter { $0.medium != Self.novelMedium }
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
            // mostly novels still means the feed continues. the shelf sets its
            // own page size and it is not ours
            next: response.items.count == Self.shelfWindow ? page + 1 : nil
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
            authors: await authors(for: document, seriesSlug: seriesSlug)
        )
    }

    // the search index's authors field goes stale for a chunk of the catalogue -
    // empty even for well-known titles - while manga/page (already queried again
    // in chapters() for scanlator names) carries it correctly. only paid when the
    // index already came back empty, and failure here degrades to no authors
    // rather than failing the whole details() call over non-critical metadata
    private func authors(for document: Detail, seriesSlug: String) async -> [String] {
        if let authors = document.authors, !authors.isEmpty { return authors }

        let page: MangaPage? = try? await fetch(
            Self.api("manga/page", [.init(name: "id", value: seriesSlug)])
        )
        return page?.mangaPage.authors?.map(\.name) ?? []
    }

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
        async let listing: ChapterList = fetch(
            Self.api(
                "manga/allChapters",
                [
                    .init(name: "mangaId", value: seriesSlug)
                ]))
        async let page: MangaPage = fetch(
            Self.api(
                "manga/page",
                [
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
        let response: ReadChapter = try await fetch(
            Self.api(
                "read/chapter",
                [
                    .init(name: "mangaId", value: seriesSlug),
                    .init(name: "chapterId", value: chapterSlug),
                ]))

        // a novel that slipped past the medium filter answers 200 with an empty
        // list, so zero pages here is the site saying "not readable" rather than
        // a chapter that happens to be short. thrown rather than returned empty,
        // or the reader opens on nothing and blames itself
        guard !response.readChapter.pages.isEmpty else { throw SourceError.noPages }

        return response.readChapter.pages.compactMap { page in
            guard let url = Self.asset(page.image) else { return nil }
            return PageURL(
                index: page.number,
                url: url,
                size: page.width.flatMap { width in
                    page.height.map { PageSize(width: width, height: $0, exactness: .exact) }
                }
            )
        }
    }
}

// MARK: - Requests

extension AtsumaruSource {
    fileprivate func fetch<Model: Decodable>(_ url: URL) async throws -> Model {
        try await network.get(url: url, headers: ["Referer": descriptor.referer.absoluteString])
    }

    fileprivate static func api(_ path: String, _ items: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: URL(string: "https://atsu.moe/api")!.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    fileprivate static func collection(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: URL(string: "https://atsu.moe/collections/manga/documents/search")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items
        return components.url!
    }

    fileprivate static let stubFields =
        "id,title,poster,posterSmall,posterMedium,mbContentRating,isAdult"
    fileprivate static let pornographic = "Pornographic"
    // requested for the same reason search does: full-size is the variant
    // that goes missing from their cdn
    fileprivate static let detailFields =
        "id,title,otherNames,synopsis,poster,posterMedium,status,isAdult,mbContentRating,tags,authors"

    fileprivate static func documentURL(id: String) -> URL {
        collection([
            .init(name: "q", value: "*"),
            .init(name: "query_by", value: "title"),
            .init(name: "filter_by", value: "id:=\(quoted(id))"),
            .init(name: "include_fields", value: detailFields),
            .init(name: "per_page", value: "1"),
        ])
    }

    fileprivate static func searchURL(
        _ query: SearchQuery, sort: SortSelection?, fields: String, gateOpen: Bool
    ) -> URL {
        var items: [URLQueryItem] = [
            // a blank search is a match-all rather than an error
            .init(name: "q", value: query.text?.isEmpty == false ? query.text! : "*"),
            .init(name: "query_by", value: queryFields),
            .init(name: "query_by_weights", value: queryWeights),
            .init(name: "include_fields", value: fields),
            .init(name: "per_page", value: String(window)),
            .init(name: "page", value: String(max(1, query.page))),
        ]

        if let sort = sort?.optionID, !sort.isEmpty {
            items.append(.init(name: "sort_by", value: sort))
        }

        var clauses = filters(query.filters)

        // the collection holds web novels - 62 of 20,104 when last probed, up
        // from 8 at the first survey - and they are indistinguishable from
        // comics until you open one: a full chapter list, every chapter at
        // pageCount 0, and read/chapter answering `{"pages": []}` with a 200.
        // so the reader gets an empty chapter rather than an error.
        //
        // not a filter option: this source does not serve novels, so it is not
        // a choice anyone makes. exclusion rather than `medium:=Comic` because
        // 132 documents carry no `medium` field at all while manga/info calls
        // them Comic - Skill Master Levels Up is one, 581 chapters - and an
        // inclusive test hides every one of them
        clauses.append("medium:!=\(quoted(novelMedium))")

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
    fileprivate static func filters(_ selections: [FilterSelection]) -> [String] {
        selections.flatMap { selection -> [String] in
            switch selection {
            case .multiSelect(let id, let included, let excluded):
                var clauses = included.map { "\(id):=\(quoted($0))" }
                if !excluded.isEmpty {
                    clauses.append("\(id):!=[\(excluded.map(quoted).joined(separator: ","))]")
                }
                return clauses

            case .select(let id, let optionID):
                return ["\(id):=\(quoted(optionID))"]

            case .number(let id, let value):
                return ["\(id):=\(value)"]

            case .text(let id, let value):
                return value.isEmpty ? [] : ["\(id):=\(quoted(value))"]
            }
        }
    }

    // backticks are typesense's own literal quoting, so an id containing a comma
    // or a space cannot split the clause it sits in
    fileprivate static func quoted(_ value: String) -> String {
        "`\(value.replacingOccurrences(of: "`", with: ""))`"
    }

    // the two backends spell one file two ways. typesense answers
    // "/static/posters/x-medium.avif" and the shelf routes answer
    // "posters/x-medium.avif" for the same bytes - so resolving either against
    // the cdn verbatim gets one of them right and 404s the other. everything is
    // reduced to its bare path and then given the one prefix that works.
    //
    // this is what made the Recently Updated covers blank while search covers
    // loaded: same series, same file, one leading segment apart. mihon's
    // extension carries the identical normalisation (removePrefix("/") then
    // removePrefix("static/"), then baseUrl + "/static/"), which is how a second
    // implementation confirms it is the site and not us
    fileprivate static func asset(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }

        var bare = Substring(path)
        while bare.hasPrefix("/") { bare = bare.dropFirst() }
        if bare.hasPrefix("static/") { bare = bare.dropFirst("static/".count) }

        return cdn.appending(path: "static").appending(path: String(bare))
    }

    fileprivate static func poster(_ path: String?) -> URL? {
        asset(path)
    }
}

// MARK: - Responses

extension AtsumaruSource {
    fileprivate struct Documents<Document: Decodable & Sendable>: Decodable, Sendable {
        let found: Int
        let hits: [Hit]

        struct Hit: Decodable, Sendable {
            let document: Document
        }
    }

    fileprivate struct Stub: Decodable, Sendable {
        let id: String
        let title: String
        let poster: String?
        let posterSmall: String?
        let posterMedium: String?
        let mbContentRating: String?
        let isAdult: Bool?
    }

    fileprivate struct HomeShelf: Decodable, Sendable {
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

    fileprivate struct Detail: Decodable, Sendable {
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

    fileprivate struct ChapterList: Decodable, Sendable {
        let chapters: [Chapter]

        struct Chapter: Decodable, Sendable {
            let id: String
            let scanlationMangaId: String?
            let title: String?
            let number: Double?
            let createdAt: Double?
        }
    }

    fileprivate struct MangaPage: Decodable, Sendable {
        let mangaPage: Page

        struct Page: Decodable, Sendable {
            let scanlators: [Scanlator]
            let authors: [Author]?
        }

        struct Scanlator: Decodable, Sendable {
            let id: String
            let name: String
        }

        // role (Author/Artist) is dropped - the app's author model is flat
        struct Author: Decodable, Sendable {
            let name: String
        }
    }

    fileprivate struct ReadChapter: Decodable, Sendable {
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

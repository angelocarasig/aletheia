//
//  MangaFireSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation

struct MangaFireSource: SourceService, AuthenticatingSource {
    let requester: AuthRequester

    private static let chapterPageSize = 200

    let descriptor = SourceDescriptor(
        slug: "mangafire",
        name: "MangaFire",
        description:
            "Free read manga online in high quality. Update hourly, No ads, No registration required. Just enjoy your manga ;)",
        icon: .mangaFire,
        languages: [.english, .chinese, .japanese, .korean],
        baseURL: URL(string: "https://mangafire.to")!,
        referer: URL(string: "https://mangafire.to")!,
        supportedFilters: [
            .number(id: "min_chap", name: "Minimum Chapters"),
            .number(id: "year_from", name: "Year From"),
            .number(id: "year_to", name: "Year To"),
            .multiSelect(
                id: "content_rating",
                name: "Content Rating",
                options: [
                    .init(id: "safe", name: "Safe"),
                    .init(id: "suggestive", name: "Suggestive"),
                    .init(id: "erotica", name: "Erotica", sensitivity: .suggestive),
                    .init(id: "pornographic", name: "Pornographic", sensitivity: .adult),
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "types",
                name: "Type",
                options: [
                    .init(id: "manga", name: "Manga"),
                    .init(id: "manhwa", name: "Manhwa"),
                    .init(id: "manhua", name: "Manhua"),
                    .init(id: "other", name: "Other"),
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "statuses",
                name: "Status",
                options: [
                    .init(id: "releasing", name: "Releasing"),
                    .init(id: "finished", name: "Finished"),
                    .init(id: "on_hiatus", name: "On Hiatus"),
                    .init(id: "discontinued", name: "Discontinued"),
                    .init(id: "not_yet_released", name: "Not Yet Released"),
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "demographics",
                name: "Demographic",
                options: [
                    .init(id: "268919", name: "Josei"),
                    .init(id: "268920", name: "Seinen"),
                    .init(id: "268917", name: "Shoujo"),
                    .init(id: "268918", name: "Shounen"),
                ],
                canExclude: false
            ),
            .select(
                id: "genres_mode",
                name: "Genre Inclusion",
                options: [
                    .init(id: "and", name: "All"),
                    .init(id: "or", name: "Any"),
                ]
            ),
            .multiSelect(
                id: "genres",
                name: "Genres",
                options: [
                    .init(id: "1", name: "Action"),
                    .init(id: "268929", name: "Adult", sensitivity: .suggestive),
                    .init(id: "78", name: "Adventure"),
                    .init(id: "3", name: "Avant Garde"),
                    .init(id: "4", name: "Boys Love"),
                    .init(id: "5", name: "Comedy"),
                    .init(id: "268921", name: "Crime"),
                    .init(id: "77", name: "Demons"),
                    .init(id: "6", name: "Drama"),
                    .init(id: "7", name: "Ecchi"),
                    .init(id: "79", name: "Fantasy"),
                    .init(id: "9", name: "Girls Love"),
                    .init(id: "10", name: "Gourmet"),
                    .init(id: "11", name: "Harem"),
                    .init(id: "268930", name: "Hentai", sensitivity: .adult),
                    .init(id: "268922", name: "Historical"),
                    .init(id: "530", name: "Horror"),
                    .init(id: "13", name: "Isekai"),
                    .init(id: "531", name: "Iyashikei"),
                    .init(id: "15", name: "Josei"),
                    .init(id: "532", name: "Kids"),
                    .init(id: "539", name: "Magic"),
                    .init(id: "268923", name: "Magical Girls"),
                    .init(id: "533", name: "Mahou Shoujo"),
                    .init(id: "534", name: "Martial Arts"),
                    .init(id: "268931", name: "Mature"),
                    .init(id: "19", name: "Mecha"),
                    .init(id: "268924", name: "Medical"),
                    .init(id: "535", name: "Military"),
                    .init(id: "21", name: "Music"),
                    .init(id: "22", name: "Mystery"),
                    .init(id: "23", name: "Parody"),
                    .init(id: "268925", name: "Philosophical"),
                    .init(id: "536", name: "Psychological"),
                    .init(id: "25", name: "Reverse Harem"),
                    .init(id: "26", name: "Romance"),
                    .init(id: "73", name: "School"),
                    .init(id: "28", name: "Sci-Fi"),
                    .init(id: "537", name: "Seinen"),
                    .init(id: "30", name: "Shoujo"),
                    .init(id: "31", name: "Shounen"),
                    .init(id: "538", name: "Slice of Life"),
                    .init(id: "268932", name: "Smut", sensitivity: .suggestive),
                    .init(id: "33", name: "Space"),
                    .init(id: "34", name: "Sports"),
                    .init(id: "75", name: "Super Power"),
                    .init(id: "268926", name: "Superhero"),
                    .init(id: "76", name: "Supernatural"),
                    .init(id: "37", name: "Suspense"),
                    .init(id: "38", name: "Thriller"),
                    .init(id: "268927", name: "Tragedy"),
                    .init(id: "39", name: "Vampire"),
                    .init(id: "268928", name: "Wuxia"),
                ],
                canExclude: true
            ),
            .select(
                id: "theme_mode",
                name: "Theme Inclusion",
                options: [
                    .init(id: "and", name: "All"),
                    .init(id: "or", name: "Any"),
                ]
            ),
            .multiSelect(
                id: "theme_ids",
                name: "Themes",
                options: [
                    .init(id: "268933", name: "Aliens"),
                    .init(id: "268934", name: "Animals"),
                    .init(id: "268935", name: "Cooking"),
                    .init(id: "268936", name: "Crossdressing"),
                    .init(id: "268937", name: "Delinquents"),
                    .init(id: "268938", name: "Demons"),
                    .init(id: "268939", name: "Genderswap"),
                    .init(id: "268940", name: "Ghosts"),
                    .init(id: "268941", name: "Gyaru"),
                    .init(id: "268942", name: "Harem"),
                    .init(id: "268943", name: "Incest", sensitivity: .suggestive),
                    .init(id: "268944", name: "Loli", sensitivity: .suggestive),
                    .init(id: "268945", name: "Mafia"),
                    .init(id: "268946", name: "Magic"),
                    .init(id: "268947", name: "Martial Arts"),
                    .init(id: "268948", name: "Military"),
                    .init(id: "268949", name: "Monster Girls"),
                    .init(id: "268950", name: "Monsters"),
                    .init(id: "268951", name: "Music"),
                    .init(id: "268952", name: "Ninja"),
                    .init(id: "268953", name: "Office Workers"),
                    .init(id: "268954", name: "Police"),
                    .init(id: "268955", name: "Post-Apocalyptic"),
                    .init(id: "268956", name: "Reincarnation"),
                    .init(id: "268957", name: "Reverse Harem"),
                    .init(id: "268958", name: "Samurai"),
                    .init(id: "268959", name: "School Life"),
                    .init(id: "268960", name: "Shota", sensitivity: .suggestive),
                    .init(id: "268961", name: "Supernatural"),
                    .init(id: "268962", name: "Survival"),
                    .init(id: "268963", name: "Time Travel"),
                    .init(id: "268964", name: "Traditional Games"),
                    .init(id: "268965", name: "Vampires"),
                    .init(id: "268966", name: "Video Games"),
                    .init(id: "268967", name: "Villainess"),
                    .init(id: "268968", name: "Virtual Reality"),
                    .init(id: "268969", name: "Zombies"),
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "languages",
                name: "Language",
                options: LanguageCode.allCases.map { .init(id: $0.rawValue, name: $0.displayName) },
                canExclude: false
            ),
        ],
        supportedSort: .init(
            options: [
                .init(id: "relevance:desc", name: "Best match"),
                .init(id: "chapter_updated_at:desc", name: "Latest update"),
                .init(id: "created_at:desc", name: "Recently added"),
                .init(id: "title:asc", name: "Title (A-Z)"),
                .init(id: "title:desc", name: "Title (Z-A)"),
                .init(id: "year:desc", name: "Year (newest)"),
                .init(id: "year:asc", name: "Year (oldest)"),
                .init(id: "score:desc", name: "Highest rated"),
                .init(id: "views_7d:desc", name: "Most viewed · 7 days"),
                .init(id: "views_30d:desc", name: "Most viewed · 30 days"),
                .init(id: "views_total:desc", name: "Most viewed · all time"),
                .init(id: "follows_total:desc", name: "Most followed"),
            ],
            defaultSort: "relevance:desc"
        )
    )

    var presets: [SourcePreset] {
        [
            .init(
                id: "latest", name: "Latest Updates", subtitle: "Freshly released chapters",
                order: 0,
                sort: .init(optionID: "chapter_updated_at:desc")),
            .init(
                id: "new", name: "New Releases", subtitle: "Recently added series", order: 1,
                sort: .init(optionID: "created_at:desc")),
            .init(
                id: "top-rated", name: "Top Rated", subtitle: "Highest scored on MangaFire",
                order: 2,
                sort: .init(optionID: "score:desc")),
            .init(
                id: "trending", name: "Trending", subtitle: "What everyone's reading now", order: 3,
                sort: .init(optionID: "views_30d:desc")),
            .init(
                id: "popular", name: "All-Time Popular", subtitle: "Most viewed of all time",
                order: 4,
                sort: .init(optionID: "views_total:desc")),
        ]
    }

    // the site root always serves the spa shell, so a 200 from it says nothing
    // about the api - ping /api/titles instead
    var pingURL: URL {
        Self.endpoint("/api/titles", [URLQueryItem(name: "limit", value: "1")])
    }

    var specification: AuthSpecification {
        AuthSpecification(
            requirements: [
                .cookie(name: "cf_clearance"),
                // optional: the spa doesn't reliably set this on first paint
                .cookie(name: "session", optional: true),
            ],
            challengeURL: descriptor.baseURL,
            userAgent: nil,
            maneuver: "Complete the check if one appears. This window closes automatically.",
            interactive: true
        )
    }

    // a bad signature also answers 403, which the default heuristic would read
    // as a cloudflare challenge - check the body for the real cause first
    func isChallenge(response: HTTPURLResponse, body: Data) -> Bool {
        let text = String(decoding: body, as: UTF8.self)
        if text.contains("Missing token.") || text.contains("Invalid token.") { return false }
        return isCloudflareChallenge(response: response, body: body)
    }
}

// MARK: - Requests

extension MangaFireSource {
    // order across keys doesn't matter to the signature, but order *within* one
    // repeated key does - the index in `key[0]`/`key[1]` binds to position, so
    // these items are handed to the signer untouched rather than re-sorted here
    private static func endpoint(_ path: String, _ items: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: URL(string: "https://mangafire.to")!, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = items + [MangaFireSigner.sign(path: path, items: items)]
        return components.url!
    }

    // requester.send hands back whatever came without checking status, so the
    // 200...299 check below is ours - otherwise a challenge page would just
    // fail json decoding instead of being recognised as a wall
    private func fetch<Model: Decodable & Sendable>(_ path: String, _ items: [URLQueryItem] = [])
        async throws -> Model
    {
        var request = URLRequest(url: Self.endpoint(path, items))
        // a clearance and safari user-agent without the headers safari would
        // send on an xhr to this endpoint is a bot signal on its own
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(descriptor.referer.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        let (data, response) = try await requester.send(request, for: self)

        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.badResponse(status: response.statusCode, response: response)
        }

        do {
            return try JSONDecoder().decode(Model.self, from: data)
        } catch let error as DecodingError {
            throw NetworkError.decoding(type: String(describing: Model.self), error: error)
        }
    }
}

// MARK: - Search

extension MangaFireSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let response: TitlesResponse = try await fetch("/api/titles", items(for: query))

        // the list payload carries no per-item rating, so adult status is
        // derived from the request itself rather than the response
        let adult = Self.stampsAdult(for: query, gateOpen: allowsAdult(for: query))

        let items = response.items.map { item in
            SeriesStub(
                slug: item.hid,
                title: item.title,
                cover: item.poster?.medium.flatMap { URL(string: $0) },
                adult: adult
            )
        }
        return SearchPage(items: items, next: response.meta.hasNext ? response.meta.page + 1 : nil)
    }

    private static let clean = ["safe", "suggestive", "erotica"]

    private static func stampsAdult(for query: SearchQuery, gateOpen: Bool) -> Bool {
        guard gateOpen else { return false }
        guard
            case .multiSelect(_, let included, _)? = query.filters.first(where: {
                $0.id == "content_rating"
            })
        else { return true }

        return included.contains("pornographic")
    }

    private func items(for query: SearchQuery) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(max(1, query.page))),
            URLQueryItem(name: "limit", value: "50"),
        ]

        // content_rating must never be omitted - an absent one returns every
        // rating including pornographic
        if !query.filters.contains(where: { $0.id == "content_rating" }) {
            let allowed = allowsAdult(for: query) ? Self.clean + ["pornographic"] : Self.clean
            items += allowed.map { URLQueryItem(name: "content_rating[]", value: $0) }
        }

        if let text = query.text, !text.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: text))
        }

        let sort = resolvedSort(for: query).optionID
        let parts = sort.split(separator: ":", maxSplits: 1)
        if let key = parts.first {
            items.append(
                URLQueryItem(
                    name: "order[\(key)]", value: parts.count > 1 ? String(parts[1]) : "desc"))
        }

        for filter in query.filters {
            switch filter {
            case .number(let id, let value):
                items.append(URLQueryItem(name: id, value: String(value)))

            case .text(let id, let value):
                items.append(URLQueryItem(name: id, value: value))

            case .select(let id, let optionID):
                items.append(URLQueryItem(name: id, value: optionID))

            case .multiSelect(let id, let included, let excluded):
                if id == "genres" {
                    items += included.map { URLQueryItem(name: "genres_in[]", value: $0) }
                    items += excluded.map { URLQueryItem(name: "genres_ex[]", value: $0) }
                } else {
                    items += included.map { URLQueryItem(name: "\(id)[]", value: $0) }
                }
            }
        }

        return items
    }

    private struct TitlesResponse: Decodable, Sendable {
        let items: [Item]
        let meta: Meta

        struct Item: Decodable, Sendable {
            let hid: String
            let title: String
            let poster: Poster?
        }
        struct Meta: Decodable, Sendable {
            let page: Int
            let hasNext: Bool
        }
    }

    private struct Poster: Decodable, Sendable {
        let small: String?
        let medium: String?
        let large: String?
    }
}

// MARK: - Details

extension MangaFireSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let response: TitleResponse = try await fetch("/api/titles/\(seriesSlug)")
        let data = response.data

        let tags =
            (data.genres ?? []).map(\.title)
            + (data.themes ?? []).map(\.title)
            + (data.demographics ?? []).map(\.title)
        let authors = (data.authors ?? []).map(\.title) + (data.artists ?? []).map(\.title)

        let cover = data.poster?.large ?? data.poster?.medium ?? data.poster?.small
        let covers = cover.flatMap { URL(string: $0) }.map { [$0] } ?? []

        let url = data.url.flatMap { URL(string: $0, relativeTo: descriptor.baseURL)?.absoluteURL }

        return SeriesDetail(
            slug: data.hid,
            title: data.title,
            altTitles: data.altTitles ?? [],
            synopsis: HTMLMarkdown.from(data.synopsisHtml ?? ""),
            url: url
                ?? descriptor.baseURL.appendingPathComponent("title").appendingPathComponent(
                    seriesSlug),
            classification: Classification(rating: data.contentRating),
            publication: Publication(status: data.status),
            covers: covers,
            tags: tags,
            authors: authors
        )
    }

    private struct TitleResponse: Decodable, Sendable {
        let data: Detail

        struct Detail: Decodable, Sendable {
            let hid: String
            let title: String
            let url: String?
            let status: String?
            let contentRating: String?
            let poster: Poster?
            let synopsisHtml: String?
            let altTitles: [String]?
            let genres: [Tag]?
            let themes: [Tag]?
            let demographics: [Tag]?
            let authors: [Tag]?
            let artists: [Tag]?
        }
        struct Tag: Decodable, Sendable {
            let title: String
        }
    }
}

// MARK: - Chapters

extension MangaFireSource {
    // no language parameter: one request set returns every language and the
    // reader's own priority ordering decides what wins - filtering per
    // language server-side would be four times the requests for the same rows
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        let first: ChaptersResponse = try await fetch(
            "/api/titles/\(seriesSlug)/chapters", Self.chapterItems(page: 1))

        var items = first.items
        let lastPage = max(1, first.meta?.lastPage ?? 1)

        if lastPage > 1 {
            items += try await withThrowingTaskGroup(of: [ChaptersResponse.Item].self) { group in
                for page in 2...lastPage {
                    group.addTask {
                        let response: ChaptersResponse = try await fetch(
                            "/api/titles/\(seriesSlug)/chapters",
                            Self.chapterItems(page: page)
                        )
                        return response.items
                    }
                }

                var collected: [ChaptersResponse.Item] = []
                for try await page in group { collected += page }
                return collected
            }
        }

        let base = descriptor.baseURL
            .appendingPathComponent("title")
            .appendingPathComponent(seriesSlug)
            .appendingPathComponent("chapter")

        var seen = Set<Int>()
        var entries: [ChapterEntry] = []

        for item in items where seen.insert(item.id).inserted {
            // mangafire serves languages we don't model (pt-br, fr, es, es-la) -
            // drop rather than default, since mislabeling one as english would
            // display it wrong instead of just omitting it
            guard let language = LanguageCode(rawValue: item.language) else { continue }

            entries.append(
                ChapterEntry(
                    slug: String(item.id),
                    title: item.name?.isEmpty == false
                        ? item.name! : "Chapter \(Self.number(item.number))",
                    number: item.number,
                    language: language,
                    scanlator: Self.scanlator(for: item.type),
                    url: base.appendingPathComponent(String(item.id)),
                    publishedDate: item.createdAt.map { Date(timeIntervalSince1970: $0) }
                        ?? .distantPast
                ))
        }

        return entries
    }

    private static func chapterItems(page: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "sort", value: "number"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(chapterPageSize)),
        ]
    }

    // official and unofficial releases sit at the same chapter number - collapsing
    // both to one scanlator name would show the reader two identical-looking rows
    private static func scanlator(for type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "official": "Official"
        case "unofficial": "Unofficial"
        default: "MangaFire"
        }
    }

    private struct ChaptersResponse: Decodable, Sendable {
        let items: [Item]
        let meta: Meta?

        struct Item: Decodable, Sendable {
            let id: Int
            let number: Double
            let name: String?
            let language: String
            let type: String?
            let createdAt: Double?
        }
        struct Meta: Decodable, Sendable {
            let lastPage: Int?
        }
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

// MARK: - Content

extension MangaFireSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        let response: ChapterContentResponse = try await fetch("/api/chapters/\(chapterSlug)")

        // dimensions arrive with the page list itself - tier 0 of the
        // page-dimensions ladder, no extra request needed
        return response.data.pages.enumerated().compactMap { index, page in
            URL(string: page.url).map {
                PageURL(
                    index: index,
                    url: $0,
                    size: page.width > 0 && page.height > 0
                        ? PageSize(width: page.width, height: page.height, exactness: .exact)
                        : nil
                )
            }
        }
    }

    private struct ChapterContentResponse: Decodable, Sendable {
        let data: Content

        struct Content: Decodable, Sendable {
            let pages: [Page]
        }
        struct Page: Decodable, Sendable {
            let url: String
            let width: Int
            let height: Int
        }
    }
}

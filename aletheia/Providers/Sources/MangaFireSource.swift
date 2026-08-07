//
//  MangaFireSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

struct MangaFireSource: SourceService, AuthenticatingSource {
    let requester: AuthRequester
    let renderer: WebRenderer
    
    private let defaultSortID = "relevance:desc"
    private let detailsPath = "title"

    let descriptor = SourceDescriptor(
        slug: "mangafire",
        name: "MangaFire",
        description: "Free read manga online in high quality. Update hourly, No ads, No registration required. Just enjoy your manga ;)",
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
                    .init(id: "erotica", name: "Erotica", nsfw: true),
                    .init(id: "pornographic", name: "Pornographic", nsfw: true)
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
                    .init(id: "other", name: "Other")
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
                    .init(id: "268918", name: "Shounen")
                ],
                canExclude: false
            ),
            .select(
                id: "genres_mode",
                name: "Genre Inclusion",
                options: [
                    .init(id: "and", name: "All"),
                    .init(id: "or", name: "Any")
                ]
            ),
            .multiSelect(
                id: "genres",
                name: "Genres",
                options: [
                    .init(id: "1", name: "Action"),
                    .init(id: "268929", name: "Adult", nsfw: true),
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
                    .init(id: "268930", name: "Hentai", nsfw: true),
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
                    .init(id: "268932", name: "Smut", nsfw: true),
                    .init(id: "33", name: "Space"),
                    .init(id: "34", name: "Sports"),
                    .init(id: "75", name: "Super Power"),
                    .init(id: "268926", name: "Superhero"),
                    .init(id: "76", name: "Supernatural"),
                    .init(id: "37", name: "Suspense"),
                    .init(id: "38", name: "Thriller"),
                    .init(id: "268927", name: "Tragedy"),
                    .init(id: "39", name: "Vampire"),
                    .init(id: "268928", name: "Wuxia")
                ],
                canExclude: true
            ),
            .select(
                id: "theme_mode",
                name: "Theme Inclusion",
                options: [
                    .init(id: "and", name: "All"),
                    .init(id: "or", name: "Any")
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
                    .init(id: "268943", name: "Incest", nsfw: true),
                    .init(id: "268944", name: "Loli", nsfw: true),
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
                    .init(id: "268960", name: "Shota", nsfw: true),
                    .init(id: "268961", name: "Supernatural"),
                    .init(id: "268962", name: "Survival"),
                    .init(id: "268963", name: "Time Travel"),
                    .init(id: "268964", name: "Traditional Games"),
                    .init(id: "268965", name: "Vampires"),
                    .init(id: "268966", name: "Video Games"),
                    .init(id: "268967", name: "Villainess"),
                    .init(id: "268968", name: "Virtual Reality"),
                    .init(id: "268969", name: "Zombies")
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "languages",
                name: "Language",
                options: [
                    .init(id: "en", name: "English"),
                    .init(id: "ja", name: "Japanese")
                ],
                canExclude: false
            )
        ],
        supportedSorts: [
            .init(
                id: "sort",
                name: "Sort",
                options: [
                    .init(id: "relevance:desc", name: "Best match"),
                    .init(id: "updated_at:desc", name: "Latest update"),
                    .init(id: "created_at:desc", name: "Recently added"),
                    .init(id: "title:asc", name: "Title (A–Z)"),
                    .init(id: "title:desc", name: "Title (Z–A)"),
                    .init(id: "year:desc", name: "Year (newest)"),
                    .init(id: "year:asc", name: "Year (oldest)"),
                    .init(id: "score:desc", name: "Highest rated"),
                    .init(id: "trending:desc", name: "Trending"),
                    .init(id: "views_7d:desc", name: "Most viewed · 7 days"),
                    .init(id: "views_30d:desc", name: "Most viewed · 30 days"),
                    .init(id: "views_total:desc", name: "Most viewed · all time"),
                    .init(id: "follows_total:desc", name: "Most followed")
                ],
                defaultIndex: 0,
                defaultAscending: false
            )
        ]
    )

    var presets: [SourcePreset] {
        [
            .init(id: "trending", name: "Trending", subtitle: "What everyone's reading now", order: 0,
                  sort: .init(optionID: "trending:desc", ascending: false)),
            .init(id: "latest", name: "Latest Updates", subtitle: "Freshly released chapters", order: 1,
                  sort: .init(optionID: "updated_at:desc", ascending: false)),
            .init(id: "new", name: "New Releases", subtitle: "Recently added series", order: 2,
                  sort: .init(optionID: "created_at:desc", ascending: false)),
            .init(id: "top-rated", name: "Top Rated", subtitle: "Highest scored on MangaFire", order: 3,
                  sort: .init(optionID: "score:desc", ascending: false)),
            .init(id: "popular", name: "All-Time Popular", subtitle: "Most viewed of all time", order: 4,
                  sort: .init(optionID: "views_total:desc", ascending: false))
        ]
    }

    var specification: AuthSpecification {
        AuthSpecification(
            requirements: [
                .cookie(name: "cf_clearance"),
                .cookie(name: "session")
            ],
            challengeURL: descriptor.baseURL,
            userAgent: nil,
            maneuver: "Leave this window open to capture cookies. This window will close automatically.",
            interactive: false
        )
    }

}

// MARK: - Search

extension MangaFireSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let url = browseURL(for: query)
        let credential = try await requester.credential(for: self)
        let json = try await renderer.sniff(url, credential: credential, matching: "/api/titles")
        let response = try JSONDecoder().decode(TitlesResponse.self, from: Data(json.utf8))

        let items = response.items.map { item in
            SeriesStub(
                slug: item.hid,
                title: item.title,
                cover: item.poster.medium.flatMap { URL(string: $0) }
            )
        }
        return SearchPage(items: items, next: response.meta.hasNext ? response.meta.page + 1 : nil)
    }

    private struct TitlesResponse: Decodable {
        let items: [Item]
        let meta: Meta

        struct Item: Decodable {
            let hid: String
            let title: String
            let poster: Poster
        }
        struct Poster: Decodable {
            let small: String?
            let medium: String?
            let large: String?
        }
        struct Meta: Decodable {
            let page: Int
            let hasNext: Bool
        }
    }

    private enum GenreFilter: String {
        case included = "genres_in"
        case excluded = "genres_ex"
    }

    private func genres(from selection: FilterSelection) -> [URLQueryItem] {
        guard case let .multiSelect(_, included, excluded) = selection else { return [] }
        return [
            (GenreFilter.included, included),
            (GenreFilter.excluded, excluded)
        ].compactMap { key, ids in
            ids.isEmpty ? nil : URLQueryItem(name: key.rawValue, value: ids.joined(separator: ","))
        }
    }

    private func browseURL(for query: SearchQuery) -> URL {
        var items: [URLQueryItem] = []

        if let text = query.text, !text.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: text))
        }
        items.append(URLQueryItem(name: "sort", value: query.sort?.optionID ?? defaultSortID))

        for filter in query.filters {
            switch filter {
            case let .number(id, value):
                items.append(URLQueryItem(name: id, value: String(value)))
            case let .text(id, value):
                items.append(URLQueryItem(name: id, value: value))
            case let .select(id, optionID):
                items.append(URLQueryItem(name: id, value: optionID))
            case let .multiSelect(id, included, _):
                if id == "genres" {
                    items.append(contentsOf: genres(from: filter))
                } else if !included.isEmpty {
                    items.append(URLQueryItem(name: id, value: included.joined(separator: ",")))
                }
            }
        }

        if query.page > 1 {
            items.append(URLQueryItem(name: "page", value: String(query.page)))
        }

        var components = URLComponents(url: descriptor.baseURL.appendingPathComponent("browse"), resolvingAgainstBaseURL: false)!
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

}

// MARK: - Details

extension MangaFireSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let pageURL = detailsURL(for: seriesSlug)
        let credential = try await requester.credential(for: self)
        let json = try await renderer.sniff(pageURL, credential: credential, matching: "/api/titles/\(seriesSlug)?")
        let data = try JSONDecoder().decode(TitleResponse.self, from: Data(json.utf8)).data

        let tags = (data.genres ?? []).map(\.title)
            + (data.themes ?? []).map(\.title)
            + (data.demographics ?? []).map(\.title)
        let authors = (data.authors ?? []).map(\.title) + (data.artists ?? []).map(\.title)

        let cover = data.poster.large ?? data.poster.medium ?? data.poster.small
        let covers = cover.flatMap { URL(string: $0) }.map { [$0] } ?? []

        return SeriesDetail(
            slug: data.hid,
            title: data.title,
            altTitles: data.altTitles ?? [],
            synopsis: HTMLMarkdown.from(data.synopsisHtml ?? ""),
            url: URL(string: data.url, relativeTo: descriptor.baseURL)?.absoluteURL ?? pageURL,
            classification: Classification(rating: data.contentRating),
            publication: Publication(status: data.status),
            covers: covers,
            tags: tags,
            authors: authors
        )
    }

    private struct TitleResponse: Decodable {
        let data: Detail

        struct Detail: Decodable {
            let hid: String
            let title: String
            let url: String
            let status: String?
            let contentRating: String?
            let poster: Poster
            let synopsisHtml: String?
            let altTitles: [String]?
            let genres: [Tag]?
            let themes: [Tag]?
            let demographics: [Tag]?
            let authors: [Tag]?
            let artists: [Tag]?
        }
        struct Poster: Decodable {
            let small: String?
            let medium: String?
            let large: String?
        }
        struct Tag: Decodable {
            let title: String
        }
    }

    private func detailsURL(for seriesSlug: String) -> URL {
        descriptor.baseURL
            .appendingPathComponent(detailsPath)
            .appendingPathComponent(seriesSlug)
    }
}

// MARK: - Chapters

extension MangaFireSource {
    // no cheap change check here - mangafire always returns the full list
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        let pageURL = detailsURL(for: seriesSlug)
        let credential = try await requester.credential(for: self)
        let pages = try await renderer.sniffPaged(
            pageURL,
            credential: credential,
            matching: "/api/titles/\(seriesSlug)/chapters",
            advancing: ".title-detail__chapters-pager button[aria-label='Next page']"
        )

        var seen = Set<Int>()
        var entries: [ChapterEntry] = []
        for json in pages {
            let items = try JSONDecoder().decode(ChaptersResponse.self, from: Data(json.utf8)).items
            for item in items where seen.insert(item.id).inserted {
                entries.append(ChapterEntry(
                    slug: String(item.id),
                    title: item.name.isEmpty ? "Chapter \(Self.number(item.number))" : item.name,
                    number: item.number,
                    language: LanguageCode(rawValue: item.language) ?? .english,
                    scanlator: "MangaFire",
                    url: pageURL.appendingPathComponent("chapter").appendingPathComponent(String(item.id)),
                    publishedDate: Date(timeIntervalSince1970: item.createdAt)
                ))
            }
        }
        return entries
    }

    private struct ChaptersResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let id: Int
            let number: Double
            let name: String
            let language: String
            let type: String
            let createdAt: Double
        }
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

// MARK: - Content

extension MangaFireSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        let readerURL = detailsURL(for: seriesSlug)
            .appendingPathComponent("chapter")
            .appendingPathComponent(chapterSlug)
        let credential = try await requester.credential(for: self)
        let json = try await renderer.sniff(readerURL, credential: credential, matching: "/api/chapters/\(chapterSlug)")
        let pages = try JSONDecoder().decode(ChapterContentResponse.self, from: Data(json.utf8)).data.pages

        // the sniffed payload carries dimensions per page, so the reader can
        // size a chapter before a single image lands. note this is richer than
        // the vrf-signed API's page DTO - moving to that would lose them
        return pages.enumerated().compactMap { index, page in
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

    private struct ChapterContentResponse: Decodable {
        let data: Content

        struct Content: Decodable {
            let pages: [Page]
        }
        struct Page: Decodable {
            let url: String
            let width: Int
            let height: Int
        }
    }
}

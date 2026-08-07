//
//  MangaDexSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// the only source with a documented public api, so it needs neither the renderer
// nor a credential - every call here is plain json
struct MangaDexSource: RevalidatingSource {
    let network: NetworkConfiguration

    private static let api = URL(string: "https://api.mangadex.org")!
    private static let uploads = URL(string: "https://uploads.mangadex.org")!
    private static let limit = 24
    private static let feedLimit = 500
    private static let feedCap = 20

    // the api's own ceiling for one cover page, then what we keep of it. every
    // kept cover becomes a row the downloader fetches to disk, so the second
    // number is a storage decision rather than a display one
    private static let coverPageLimit = 100
    private static let coverLimit = 20

    let descriptor = SourceDescriptor(
        slug: "mangadex",
        name: "MangaDex",
        description: "A community-run scanlation catalogue. No ads, no tracking, and the widest language coverage of any source.",
        icon: .mangaDex,
        languages: [.english, .japanese, .korean, .chinese],
        baseURL: URL(string: "https://mangadex.org")!,
        referer: URL(string: "https://mangadex.org")!,
        supportedFilters: [
            .multiSelect(
                id: "contentRating",
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
                id: "status",
                name: "Status",
                options: [
                    .init(id: "ongoing", name: "Ongoing"),
                    .init(id: "completed", name: "Completed"),
                    .init(id: "hiatus", name: "Hiatus"),
                    .init(id: "cancelled", name: "Cancelled")
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "publicationDemographic",
                name: "Demographic",
                options: [
                    .init(id: "shounen", name: "Shounen"),
                    .init(id: "shoujo", name: "Shoujo"),
                    .init(id: "seinen", name: "Seinen"),
                    .init(id: "josei", name: "Josei")
                ],
                canExclude: false
            ),
            // the api takes originalLanguage as a repeated param, same as the rest
            .multiSelect(
                id: "originalLanguage",
                name: "Original Language",
                options: [
                    .init(id: "ja", name: "Japanese"),
                    .init(id: "ko", name: "Korean"),
                    .init(id: "zh", name: "Chinese"),
                    .init(id: "en", name: "English")
                ],
                canExclude: false
            ),
            .number(id: "year", name: "Year"),
            // uuids from https://api.mangadex.org/manga/tag - the api takes them
            // as includedTags[]/excludedTags[], so this one filter drives both
            .multiSelect(
                id: "tags",
                name: "Tags",
                options: [
                    .init(id: "b11fda93-8f1d-4bef-b2ed-8803d3733170", name: "4-Koma"),
                    .init(id: "391b0423-d847-456f-aff0-8b0cfc03066b", name: "Action"),
                    .init(id: "f4122d1c-3b44-44d0-9936-ff7502c39ad3", name: "Adaptation"),
                    .init(id: "87cc87cd-a395-47af-b27a-93258283bbc6", name: "Adventure"),
                    .init(id: "e64f6742-c834-471d-8d72-dd51fc02b835", name: "Aliens"),
                    .init(id: "3de8c75d-8ee3-48ff-98ee-e20a65c86451", name: "Animals"),
                    .init(id: "51d83883-4103-437c-b4b1-731cb73d786c", name: "Anthology"),
                    .init(id: "0a39b5a1-b235-4886-a747-1d05d216532d", name: "Award Winning"),
                    .init(id: "4d32cc48-9f00-4cca-9b5a-a839f0764984", name: "Comedy"),
                    .init(id: "ea2bc92d-1c26-4930-9b7c-d5c0dc1b6869", name: "Cooking"),
                    .init(id: "5ca48985-9a9d-4bd8-be29-80dc0303db72", name: "Crime"),
                    .init(id: "9ab53f92-3eed-4e9b-903a-917c86035ee3", name: "Crossdressing"),
                    .init(id: "da2d50ca-3018-4cc0-ac7a-6b7d472a29ea", name: "Delinquents"),
                    .init(id: "39730448-9a5f-48a2-85b0-a70db87b1233", name: "Demons"),
                    .init(id: "b13b2a48-c720-44a9-9c77-39c9979373fb", name: "Doujinshi"),
                    .init(id: "b9af3a63-f058-46de-a9a0-e0c13906197a", name: "Drama"),
                    .init(id: "7b2ce280-79ef-4c09-9b58-12b7c23a9b78", name: "Fan Colored"),
                    .init(id: "cdc58593-87dd-415e-bbc0-2ec27bf404cc", name: "Fantasy"),
                    .init(id: "f5ba408b-0e7a-484d-8d49-4e9125ac96de", name: "Full Color"),
                    .init(id: "2bd2e8d0-f146-434a-9b51-fc9ff2c5fe6a", name: "Genderswap"),
                    .init(id: "3bb26d85-09d5-4d2e-880c-c34b974339e9", name: "Ghosts"),
                    .init(id: "b29d6a3d-1569-4e7a-8caf-7557bc92cd5d", name: "Gore"),
                    .init(id: "fad12b5e-68ba-460e-b933-9ae8318f5b65", name: "Gyaru"),
                    .init(id: "aafb99c1-7f60-43fa-b75f-fc9502ce29c7", name: "Harem"),
                    .init(id: "33771934-028e-4cb3-8744-691e866a923e", name: "Historical"),
                    .init(id: "cdad7e68-1419-41dd-bdce-27753074a640", name: "Horror"),
                    .init(id: "5bd0e105-4481-44ca-b6e7-7544da56b1a3", name: "Incest", nsfw: true),
                    .init(id: "ace04997-f6bd-436e-b261-779182193d3d", name: "Isekai"),
                    .init(id: "2d1f5d56-a1e5-4d0d-a961-2193588b08ec", name: "Loli"),
                    .init(id: "3e2b8dae-350e-4ab8-a8ce-016e844b9f0d", name: "Long Strip"),
                    .init(id: "85daba54-a71c-4554-8a28-9901a8b0afad", name: "Mafia"),
                    .init(id: "a1f53773-c69a-4ce5-8cab-fffcd90b1565", name: "Magic"),
                    .init(id: "81c836c9-914a-4eca-981a-560dad663e73", name: "Magical Girls"),
                    .init(id: "799c202e-7daa-44eb-9cf7-8a3c0441531e", name: "Martial Arts"),
                    .init(id: "50880a9d-5440-4732-9afb-8f457127e836", name: "Mecha"),
                    .init(id: "c8cbe35b-1b2b-4a3f-9c37-db84c4514856", name: "Medical"),
                    .init(id: "ac72833b-c4e9-4878-b9db-6c8a4a99444a", name: "Military"),
                    .init(id: "dd1f77c5-dea9-4e2b-97ae-224af09caf99", name: "Monster Girls"),
                    .init(id: "36fd93ea-e8b8-445e-b836-358f02b3d33d", name: "Monsters"),
                    .init(id: "f42fbf9e-188a-447b-9fdc-f19dc1e4d685", name: "Music"),
                    .init(id: "ee968100-4191-4968-93d3-f82d72be7e46", name: "Mystery"),
                    .init(id: "489dd859-9b61-4c37-af75-5b18e88daafc", name: "Ninja"),
                    .init(id: "92d6d951-ca5e-429c-ac78-451071cbf064", name: "Office Workers"),
                    .init(id: "320831a8-4026-470b-94f6-8353740e6f04", name: "Official Colored"),
                    .init(id: "0234a31e-a729-4e28-9d6a-3f87c4966b9e", name: "Oneshot"),
                    .init(id: "b1e97889-25b4-4258-b28b-cd7f4d28ea9b", name: "Philosophical"),
                    .init(id: "df33b754-73a3-4c54-80e6-1a74a8058539", name: "Police"),
                    .init(id: "9467335a-1b83-4497-9231-765337a00b96", name: "Post-Apocalyptic"),
                    .init(id: "3b60b75c-a2d7-4860-ab56-05f391bb889c", name: "Psychological"),
                    .init(id: "0bc90acb-ccc1-44ca-a34a-b9f3a73259d0", name: "Reincarnation"),
                    .init(id: "65761a2a-415e-47f3-bef2-a9dababba7a6", name: "Reverse Harem"),
                    .init(id: "423e2eae-a7a2-4a8b-ac03-a8351462d71d", name: "Romance"),
                    .init(id: "81183756-1453-4c81-aa9e-f6e1b63be016", name: "Samurai"),
                    .init(id: "caaa44eb-cd40-4177-b930-79d3ef2afe87", name: "School Life"),
                    .init(id: "256c8bd9-4904-4360-bf4f-508a76d67183", name: "Sci-Fi"),
                    .init(id: "891cf039-b895-47f0-9229-bef4c96eccd4", name: "Self-Published"),
                    .init(id: "97893a4c-12af-4dac-b6be-0dffb353568e", name: "Sexual Violence", nsfw: true),
                    .init(id: "ddefd648-5140-4e5f-ba18-4eca4071d19b", name: "Shota"),
                    .init(id: "e5301a23-ebd9-49dd-a0cb-2add944c7fe9", name: "Slice of Life"),
                    .init(id: "69964a64-2f90-4d33-beeb-f3ed2875eb4c", name: "Sports"),
                    .init(id: "7064a261-a137-4d3a-8848-2d385de3a99c", name: "Superhero"),
                    .init(id: "eabc5b4c-6aff-42f3-b657-3e90cbd00b75", name: "Supernatural"),
                    .init(id: "5fff9cde-849c-4d78-aab0-0d52b2ee1d25", name: "Survival"),
                    .init(id: "07251805-a27e-4d59-b488-f0bfbec15168", name: "Thriller"),
                    .init(id: "292e862b-2d17-4062-90a2-0356caa4ae27", name: "Time Travel"),
                    .init(id: "31932a7e-5b8e-49a6-9f12-2afa39dc544c", name: "Traditional Games"),
                    .init(id: "f8f62932-27da-4fe4-8ee1-6779a8c5edba", name: "Tragedy"),
                    .init(id: "d7d1730f-6eb0-4ba6-9437-602cac38664c", name: "Vampires"),
                    .init(id: "9438db5a-7e2a-4ac0-b39e-e0d95a34b8a8", name: "Video Games"),
                    .init(id: "d14322ac-4d6f-4e9b-afd9-629d5f4d8a41", name: "Villainess"),
                    .init(id: "8c86611e-fab7-4986-9dec-d1a2f44acdd5", name: "Virtual Reality"),
                    .init(id: "e197df38-d0e7-43b5-9b09-2842d0c326dd", name: "Web Comic"),
                    .init(id: "acc803a4-c95a-4c22-86fc-eb6b582d82a2", name: "Wuxia"),
                    .init(id: "631ef465-9aba-4afb-b0fc-ea10efe274a8", name: "Zombies")
                ],
                canExclude: true
            )
        ],
        // direction is baked into each option id, the same as the other sources -
        // the api names its axes as order[key]=dir and this maps straight through
        supportedSorts: [
            .init(
                id: "sort",
                name: "Sort",
                options: [
                    .init(id: "followedCount:desc", name: "Most followed"),
                    .init(id: "relevance:desc", name: "Best match"),
                    .init(id: "latestUploadedChapter:desc", name: "Latest chapter"),
                    .init(id: "createdAt:desc", name: "Recently added"),
                    .init(id: "rating:desc", name: "Highest rated"),
                    .init(id: "year:desc", name: "Newest"),
                    .init(id: "title:asc", name: "Title (A–Z)")
                ],
                defaultIndex: 0,
                defaultAscending: false
            )
        ]
    )

    var presets: [SourcePreset] {
        [
            .init(id: "popular", name: "Popular", subtitle: "Most followed on MangaDex", order: 0,
                  sort: .init(optionID: "followedCount:desc", ascending: false)),
            .init(id: "latest", name: "Latest Updates", subtitle: "Freshly uploaded chapters", order: 1,
                  sort: .init(optionID: "latestUploadedChapter:desc", ascending: false)),
            .init(id: "new", name: "New Releases", subtitle: "Recently added titles", order: 2,
                  sort: .init(optionID: "createdAt:desc", ascending: false)),
            .init(id: "top-rated", name: "Top Rated", subtitle: "Highest rated by the community", order: 3,
                  sort: .init(optionID: "rating:desc", ascending: false))
        ]
    }
}

// MARK: - Search

extension MangaDexSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let offset = max(0, query.page - 1) * Self.limit
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(Self.limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "includes[]", value: "cover_art"),
            .init(name: "hasAvailableChapters", value: "true")
        ]

        if let text = query.text, !text.isEmpty {
            items.append(.init(name: "title", value: text))
        }

        items += Self.parameters(for: query.filters)

        // relevance only means anything alongside a title, and the api rejects it
        // without one
        let sort = query.sort?.optionID ?? "followedCount:desc"
        let usable = (sort == "relevance:desc" && (query.text ?? "").isEmpty) ? "followedCount:desc" : sort
        items += Self.order(usable)

        let response: MangaList = try await network.get(url: Self.url("manga", items))
        let stubs = response.data.compactMap(Self.stub)
        let seen = response.offset + response.data.count

        return SearchPage(items: stubs, next: seen < response.total ? query.page + 1 : nil)
    }

    private static func stub(from entry: Manga) -> SeriesStub? {
        SeriesStub(
            slug: entry.id,
            title: title(from: entry.attributes.title, falling: entry.attributes.altTitles),
            cover: cover(for: entry)
        )
    }
}

// MARK: - Details

extension MangaDexSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let items: [URLQueryItem] = [
            .init(name: "includes[]", value: "cover_art"),
            .init(name: "includes[]", value: "author"),
            .init(name: "includes[]", value: "artist")
        ]

        // the manga entity carries exactly one cover_art relationship no matter
        // what is included, so the rest of the set needs its own request. it is
        // independent of the entity, so it runs alongside rather than after
        async let listing = coverListing(for: seriesSlug)

        let response: MangaEnvelope = try await network.get(url: Self.url("manga/\(seriesSlug)", items))
        let entry = response.data
        let attributes = entry.attributes

        // every title is a language map, and a series with no english entry still
        // has to be called something
        let names = attributes.altTitles.flatMap { $0.values }

        return SeriesDetail(
            slug: entry.id,
            title: Self.title(from: attributes.title, falling: attributes.altTitles),
            altTitles: Array(Set(names)).sorted(),
            synopsis: Self.text(from: attributes.description) ?? "",
            url: descriptor.baseURL.appendingPathComponent("title").appendingPathComponent(entry.id),
            classification: Self.classification(attributes.contentRating),
            publication: Self.publication(attributes.status),
            covers: Self.covers(
                from: await listing,
                for: entry,
                language: attributes.originalLanguage
            ),
            tags: attributes.tags.compactMap { Self.text(from: $0.attributes.name) },
            authors: entry.relationships
                .filter { $0.type == "author" || $0.type == "artist" }
                .compactMap { $0.attributes?.name }
        )
    }
}

// MARK: - Chapters

extension MangaDexSource {
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        guard case let .changed(entries) = try await walk(seriesSlug, stored: nil) else { return [] }
        return entries
    }

    // the feed states its own total in the first response, so a matching count
    // answers the whole question before the rest of the pages are asked for
    func chapters(seriesSlug: String, stored: Int) async throws -> ChapterRevalidation {
        try await walk(seriesSlug, stored: stored)
    }

    private func walk(_ seriesSlug: String, stored: Int?) async throws -> ChapterRevalidation {
        var entries: [ChapterEntry] = []
        var offset = 0

        for _ in 0..<Self.feedCap {
            var items: [URLQueryItem] = [
                .init(name: "limit", value: String(Self.feedLimit)),
                .init(name: "offset", value: String(offset)),
                .init(name: "includes[]", value: "scanlation_group"),
                .init(name: "order[chapter]", value: "asc")
            ]
            items += descriptor.languages.map { .init(name: "translatedLanguage[]", value: $0.rawValue) }
            items += ["safe", "suggestive", "erotica", "pornographic"].map {
                .init(name: "contentRating[]", value: $0)
            }

            let response: ChapterList = try await network.get(url: Self.url("manga/\(seriesSlug)/feed", items))

            if offset == 0, let stored, response.total == stored { return .unchanged }

            entries += response.data.compactMap(Self.entry)
            offset += response.data.count

            if response.data.isEmpty || offset >= response.total { break }
        }

        return .changed(entries)
    }

    private static func entry(from chapter: Chapter) -> ChapterEntry? {
        let attributes = chapter.attributes

        // an external chapter lives on another site entirely and has no pages here
        guard attributes.externalUrl == nil else { return nil }

        let scanlator = chapter.relationships
            .first { $0.type == "scanlation_group" }?
            .attributes?.name

        return ChapterEntry(
            slug: chapter.id,
            title: attributes.title ?? "",
            number: attributes.chapter.flatMap(Double.init) ?? 0,
            // the feed is asked for our four, but a code outside them should
            // downgrade rather than drop the chapter
            language: attributes.translatedLanguage.flatMap(LanguageCode.init) ?? .english,
            scanlator: scanlator ?? "Unknown",
            url: URL(string: "https://mangadex.org/chapter/\(chapter.id)")!,
            publishedDate: date(from: attributes.publishAt)
        )
    }
}

// MARK: - Content

extension MangaDexSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        let response: AtHome = try await network.get(url: Self.url("at-home/server/\(chapterSlug)", []))

        guard let base = URL(string: response.baseUrl) else { throw URLError(.badServerResponse) }
        let directory = base
            .appendingPathComponent("data")
            .appendingPathComponent(response.chapter.hash)

        return response.chapter.data.enumerated().map { index, name in
            PageURL(index: index, url: directory.appendingPathComponent(name))
        }
    }
}

// MARK: - Requests

extension MangaDexSource {
    private static func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    // sort ids are the request's own key:direction pair, so they map straight
    // through and search() never has to translate
    private static func order(_ sort: String) -> [URLQueryItem] {
        let parts = sort.split(separator: ":")
        guard parts.count == 2 else { return [] }
        return [.init(name: "order[\(parts[0])]", value: String(parts[1]))]
    }

    private static func parameters(for filters: [FilterSelection]) -> [URLQueryItem] {
        filters.flatMap { filter -> [URLQueryItem] in
            switch filter {
            // tags are the only excludable axis, and the api spells the two sides
            // as separate parameters rather than one with a sign
            case let .multiSelect("tags", included, excluded):
                return included.map { .init(name: "includedTags[]", value: $0) }
                    + excluded.map { .init(name: "excludedTags[]", value: $0) }

            case let .multiSelect(id, included, _):
                return included.map { .init(name: "\(id)[]", value: $0) }
            case let .number(id, value):
                return [.init(name: id, value: String(value))]
            case let .select(id, optionID):
                return [.init(name: id, value: optionID)]
            case let .text(id, value):
                return [.init(name: id, value: value)]
            }
        }
    }
}

// MARK: - Mapping

extension MangaDexSource {
    // english when it exists, otherwise whatever the series was published as
    private static func text(from map: [String: String]?) -> String? {
        guard let map, !map.isEmpty else { return nil }
        return map["en"] ?? map.sorted { $0.key < $1.key }.first?.value
    }

    // english, then romanised original, then the original script. mangadex keeps
    // romanisations under a "-ro" locale, so a japanese series usually carries
    // both "ja" and "ja-ro" and the romaji is the one worth showing
    private static let titlePriority = ["en", "ja-ro", "ko-ro", "zh-ro", "ja", "ko", "zh"]

    private static func title(from primary: [String: String], falling alternates: [[String: String]]) -> String {
        // pooled rather than searched map by map: `title` holds the original
        // language and the romanisation lives in altTitles, so going map by map
        // returns the japanese before it ever reaches the romaji one entry later.
        // first occurrence of a locale wins, and primary is walked first
        var pool: [String: String] = [:]
        for map in [primary] + alternates {
            for (locale, name) in map where pool[locale] == nil && !name.isEmpty {
                pool[locale] = name
            }
        }

        for locale in titlePriority {
            if let name = pool[locale] { return name }
        }

        // an unlisted locale: still prefer anything romanised over raw script.
        // sorted so the pick is stable rather than whatever the dictionary yields
        let keys = pool.keys.sorted()
        if let romanised = keys.first(where: { $0.hasSuffix("-ro") }) { return pool[romanised]! }
        return keys.first.flatMap { pool[$0] } ?? "Untitled"
    }

    private static func coverURL(_ manga: String, _ file: String) -> URL {
        uploads
            .appendingPathComponent("covers")
            .appendingPathComponent(manga)
            .appendingPathComponent(file)
    }

    private static func cover(for entry: Manga) -> URL? {
        guard let file = entry.relationships
            .first(where: { $0.type == "cover_art" })?
            .attributes?.fileName
        else { return nil }

        return coverURL(entry.id, file)
    }

    // a failed listing is not a failed details - the entity's own cover still
    // stands, and a series with one cover is what every other source gives
    private func coverListing(for id: String) async -> [CoverArt] {
        let items: [URLQueryItem] = [
            .init(name: "manga[]", value: id),
            .init(name: "limit", value: String(Self.coverPageLimit)),
            .init(name: "order[volume]", value: "asc")
        ]

        let response: CoverList? = try? await network.get(url: Self.url("cover", items))
        return response?.data ?? []
    }

    // covers are filed per volume per language, and a long-running series carries
    // several editions of the same volume - 85 japanese files across 43 volumes is
    // ordinary. the picker wants one of each volume in the language it was drawn
    // in, not every reprint, and every row here is an image downloaded to disk
    private static func covers(from listing: [CoverArt], for entry: Manga, language: String?) -> [URL] {
        let native = listing.filter { $0.attributes.locale == language }
        let pool = native.isEmpty ? listing : native

        // alternate editions are filed as 1.1, 1.2 against the same volume, so
        // keying on the whole number spends the budget on twenty different
        // volumes rather than seven of them three times over
        var volumes: Set<Substring> = []
        var urls: [URL] = []
        for art in pool {
            let volume = art.attributes.volume ?? ""
            guard volumes.insert(volume.prefix { $0 != "." }).inserted else { continue }
            urls.append(coverURL(entry.id, art.attributes.fileName))
        }

        // the search result carries the entity's cover, and the preferred pick is
        // resolved by matching against it - so it has to be present, and first
        if let primary = cover(for: entry) {
            urls.removeAll { $0 == primary }
            urls.insert(primary, at: 0)
        }

        return Array(urls.prefix(coverLimit))
    }

    private static func classification(_ rating: String?) -> Classification {
        switch rating {
        case "safe": .Safe
        case "suggestive": .Suggestive
        case "erotica", "pornographic": .Explicit
        default: .Unknown
        }
    }

    private static func publication(_ status: String?) -> Publication {
        switch status {
        case "ongoing": .Ongoing
        case "completed": .Completed
        case "hiatus": .Hiatus
        case "cancelled": .Cancelled
        default: .Unknown
        }
    }

    // parsed here rather than by the shared decoder, whose strategy is tuned for
    // other sources and would fail the whole response on one odd timestamp
    private static func date(from value: String?) -> Date {
        guard let value else { return .distantPast }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: value) { return parsed }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? .distantPast
    }
}

// MARK: - DTOs

extension MangaDexSource {
    private struct MangaList: Decodable {
        let data: [Manga]
        let limit: Int
        let offset: Int
        let total: Int
    }

    private struct MangaEnvelope: Decodable {
        let data: Manga
    }

    private struct Manga: Decodable {
        let id: String
        let attributes: Attributes
        let relationships: [Relationship]

        struct Attributes: Decodable {
            let title: [String: String]
            let altTitles: [[String: String]]
            let description: [String: String]?
            let status: String?
            let contentRating: String?
            let originalLanguage: String?
            let tags: [Tag]
        }

        struct Tag: Decodable {
            let attributes: TagAttributes

            struct TagAttributes: Decodable {
                let name: [String: String]?
            }
        }
    }

    private struct ChapterList: Decodable {
        let data: [Chapter]
        let total: Int
    }

    private struct Chapter: Decodable {
        let id: String
        let attributes: Attributes
        let relationships: [Relationship]

        struct Attributes: Decodable {
            let title: String?
            let chapter: String?
            let translatedLanguage: String?
            let externalUrl: String?
            let publishAt: String?
        }
    }

    // one shape covers every relationship kind - only the fields we read are
    // declared, and all of them are optional because which arrive depends on
    // what the request asked to include
    private struct Relationship: Decodable {
        let type: String
        let attributes: Attributes?

        struct Attributes: Decodable {
            let name: String?
            let fileName: String?
        }
    }

    private struct CoverList: Decodable {
        let data: [CoverArt]
    }

    private struct CoverArt: Decodable {
        let attributes: Attributes

        struct Attributes: Decodable {
            let fileName: String
            let volume: String?
            let locale: String?
        }
    }

    private struct AtHome: Decodable {
        let baseUrl: String
        let chapter: Chapter

        struct Chapter: Decodable {
            let hash: String
            let data: [String]
        }
    }
}

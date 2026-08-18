//
//  ScansGGSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// a flat public json api with no key, no signing and no renderer. two things
// shape this file: everything is keyed by integer id rather than a slug, and the
// endpoint that searches cannot rank while the endpoints that rank cannot
// search - so the rankings arrive as preset shelves through SearchQuery.route
struct ScansGGSource: SourceService {
    let network: NetworkConfiguration

    private static let api = URL(string: "https://api.scans.gg")!
    private static let cdn = URL(string: "https://cdn.scans.gg/uploads")!
    private static let limit = 21

    // a shelf shows a handful of covers and the release feed cannot be filtered
    // server-side, so it is over-fetched and trimmed
    private static let shelfLimit = 14
    private static let shelfFetch = 28

    let descriptor = SourceDescriptor(
        slug: "scansgg",
        name: "Scans.gg",
        description:
            "Read endless series. A community-run library of manhwa, manhua and manga, uploaded and translated by scanlation groups.",
        icon: .scansGG,
        languages: [.english],
        baseURL: URL(string: "https://scans.gg")!,
        referer: URL(string: "https://scans.gg")!,
        supportedFilters: [
            .multiSelect(
                id: "q_type",
                name: "Type",
                options: [
                    .init(id: "1", name: "Comic"),
                    .init(id: "2", name: "Manga"),
                    .init(id: "3", name: "Manhwa"),
                    .init(id: "4", name: "Manhua"),
                    .init(id: "5", name: "Mangatoon"),
                    .init(id: "6", name: "Webtoon"),
                    .init(id: "7", name: "One Shot"),
                    .init(id: "8", name: "Doujinshi"),
                ],
                canExclude: false
            ),
            // six of the site's seven. Upcoming (5) is deliberately absent, so
            // there is no way to ask for series that have not started
            .multiSelect(
                id: "q_status",
                name: "Status",
                options: [
                    .init(id: "1", name: "Ongoing"),
                    .init(id: "2", name: "Completed"),
                    .init(id: "3", name: "Hiatus"),
                    .init(id: "4", name: "Dropped"),
                    .init(id: "6", name: "Paused"),
                    .init(id: "7", name: "Cancelled"),
                ],
                canExclude: false
            ),
            // excludable because excluded_tags exists - the same undocumented
            // parameter the adult gate rides on
            .multiSelect(
                id: "q_tags",
                name: "Tags",
                options: Tag.options,
                canExclude: true
            ),
        ],
        // the searchable endpoint takes no sort parameter at all and always
        // returns newest-first, so one option is the whole honest axis. the
        // rankings this site does have cannot narrow, and ship as presets below
        supportedSort: .init(
            options: [.init(id: "recent", name: "Recently Added")],
            defaultSort: "recent"
        )
    )

    var presets: [SourcePreset] {
        [
            .init(
                id: "popular-daily", name: "Trending Today",
                subtitle: "Most read in the last 24 hours", order: 0, route: "popular:daily"),
            .init(
                id: "latest", name: "Latest Updates",
                subtitle: "Freshly released chapters", order: 1, route: "latest"),
            // the plain query - no sort, no filters, id DESC - so it needs no route
            .init(
                id: "new", name: "New Series",
                subtitle: "Recently added to the catalogue", order: 2),
            .init(
                id: "popular-monthly", name: "Popular This Month",
                subtitle: "Most read over the past month", order: 3, route: "popular:monthly"),
            .init(
                id: "popular-alltime", name: "Popular All Time",
                subtitle: "The catalogue's most read", order: 4, route: "popular:1year"),
        ]
    }
}

// MARK: - Tags

extension ScansGGSource {
    // declared once and read three ways: the filter options, the id-to-name map
    // details() needs, and the adult set that drives both the request gate and
    // the per-item stamp. `GET /tags` is what tells you this has drifted
    struct Tag {
        let id: Int
        let name: String
        let sensitivity: SourceFilter.Sensitivity

        init(_ id: Int, _ name: String, _ sensitivity: SourceFilter.Sensitivity = .none) {
            self.id = id
            self.name = name
            self.sensitivity = sensitivity
        }
    }

    static let tags: [Tag] = [
        .init(1, "Fantasy"), .init(2, "Romance"), .init(3, "Shoujo"), .init(4, "Comedy"),
        .init(5, "Drama"), .init(6, "Slice Of Life"), .init(7, "School Life"), .init(8, "Thriller"),
        .init(9, "Josei"), .init(10, "Action"), .init(11, "Seinen"), .init(12, "Historical"),
        .init(13, "Shounen"), .init(14, "Sports"), .init(15, "Supernatural"),
        .init(16, "Adventure"),
        .init(17, "Sci-fi"), .init(18, "Martial Arts"), .init(19, "Mystery"), .init(20, "Horror"),
        .init(21, "Mature", .suggestive), .init(22, "Psychological"), .init(23, "Suspense"),
        .init(24, "Gender Bender"), .init(25, "Tragedy"), .init(26, "Harem"),
        .init(27, "Boys Love", .suggestive), .init(28, "Shounen Ai"),
        .init(29, "Yaoi", .suggestive),
        .init(30, "Shoujo Ai"), .init(31, "Yuri", .suggestive), .init(32, "Gourmet"),
        .init(33, "Adult", .adult), .init(34, "Erotica", .adult), .init(35, "Smut", .adult),
        .init(36, "Music"), .init(37, "Ecchi", .suggestive), .init(38, "Shotacon", .adult),
        .init(39, "Mecha"), .init(40, "Hentai", .adult), .init(41, "Girls Love", .suggestive),
        .init(42, "Doujinshi", .suggestive), .init(43, "Mahou Shoujo"),
        .init(44, "Lolicon", .adult),
        .init(45, "Award Winning"), .init(46, "Avant Garde"), .init(47, "Survival"),
        .init(48, "Male Protagonist"), .init(49, "Regression"),
    ]

    static let options: [SourceFilter.Option] = tags.map {
        .init(id: String($0.id), name: $0.name, sensitivity: $0.sensitivity)
    }

    private static let names: [Int: String] = Dictionary(
        uniqueKeysWithValues: tags.map { ($0.id, $0.name) }
    )

    private static let adult: Set<Int> = Set(tags.filter { $0.sensitivity == .adult }.map(\.id))
    private static let suggestive: Set<Int> = Set(
        tags.filter { $0.sensitivity == .suggestive }.map(\.id))
}

extension ScansGGSource.Tag {
    static var options: [SourceFilter.Option] { ScansGGSource.options }
}

// MARK: - Search

extension ScansGGSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        switch Route(query.route) {
        case .popular(let window): try await popular(window, gate: query)
        case .latest: try await latest(page: query.page, gate: query)
        case .none: try await browse(query)
        }
    }

    private enum Route {
        case popular(String)
        case latest
        case none

        init(_ raw: String?) {
            guard let raw else {
                self = .none
                return
            }
            if raw == "latest" {
                self = .latest
                return
            }
            if raw.hasPrefix("popular:") {
                self = .popular(String(raw.dropFirst(8)))
                return
            }
            self = .none
        }
    }

    // the only shape that honours text and filters, and the only one that pages
    private func browse(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(Self.limit)),
            .init(name: "offset", value: String(max(0, query.page - 1) * Self.limit)),
        ]

        if let text = query.text, !text.isEmpty {
            items.append(.init(name: "q", value: text))
        }

        items += Self.parameters(for: query.filters)
        items.append(Self.exclusions(for: query, gateOpen: allowsAdult(for: query)))

        let rows: [SeriesDTO] = try await get("series", items)
        return SearchPage(
            items: rows.map(Self.stub), next: rows.count == Self.limit ? query.page + 1 : nil)
    }

    // ranked by views inside a window. ignores text, every filter and both
    // pagination parameters - but not excluded_tags, which is the only reason
    // this can be shown to someone who has not opened the gate
    private func popular(_ window: String, gate: SearchQuery) async throws -> SearchPage<SeriesStub>
    {
        let items: [URLQueryItem] = [
            .init(name: "popular", value: window),
            .init(name: "limit", value: String(Self.shelfLimit)),
            Self.exclusions(for: gate, gateOpen: allowsAdult(for: gate)),
        ]

        let rows: [SeriesDTO] = try await get("series", items)
        // there is no page 2 - offset and page are both ignored on this route
        return SearchPage(items: rows.map(Self.stub), next: nil)
    }

    // series ranked by newest chapter. the one route excluded_tags does NOT
    // reach, so the gate is applied here instead - over-fetched so trimming
    // cannot leave the shelf short
    private func latest(page: Int, gate: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let items: [URLQueryItem] = [
            .init(name: "sort", value: "date"),
            .init(name: "page", value: String(max(1, page))),
            .init(name: "limit", value: String(Self.shelfFetch)),
            .init(name: "chapters", value: "true"),
            .init(name: "series_details", value: "true"),
        ]

        let rows: [SeriesDTO] = try await get("chapters", items)
        let more = rows.count == Self.shelfFetch

        let allowed = allowsAdult(for: gate)
        let kept = allowed ? rows : rows.filter { Self.adult.isDisjoint(with: $0.tags) }

        return SearchPage(
            items: kept.prefix(Self.shelfLimit).map(Self.stub), next: more ? page + 1 : nil)
    }

    private static func parameters(for filters: [FilterSelection]) -> [URLQueryItem] {
        filters.compactMap { selection in
            switch selection {
            case .multiSelect(let id, let included, _) where !included.isEmpty:
                return .init(name: id, value: array(included))
            case .select(let id, let optionID):
                return .init(name: id, value: array([optionID]))
            case .multiSelect, .text, .number:
                return nil
            }
        }
    }

    // one parameter carries two things: whatever tags the reader excluded, and -
    // unless they opened the gate - every adult tag. shut has to mean the request
    // excludes rather than stays quiet, and this is the only lever that says so
    private static func exclusions(for query: SearchQuery, gateOpen: Bool) -> URLQueryItem {
        var ids: Set<Int> = gateOpen ? [] : adult

        for case .multiSelect(let id, _, let excluded) in query.filters where id == "q_tags" {
            ids.formUnion(excluded.compactMap(Int.init))
        }

        return .init(name: "excluded_tags", value: array(ids.sorted().map(String.init)))
    }

    // every array parameter is a json literal rather than repeated keys
    private static func array(_ values: [String]) -> String {
        "[\(values.joined(separator: ","))]"
    }

    // the item's own tags, never content_rating - 2,984 series tagged Hentai
    // report themselves as rating 1, so the field can never guarantee a false
    private static func stub(from row: SeriesDTO) -> SeriesStub {
        SeriesStub(
            slug: String(row.id),
            title: row.title,
            cover: cover(row.cover),
            adult: !adult.isDisjoint(with: row.tags)
        )
    }
}

// MARK: - Details

extension ScansGGSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let row: SeriesDTO = try await get("series", [.init(name: "id", value: seriesSlug)])

        return SeriesDetail(
            slug: String(row.id),
            title: row.title,
            altTitles: row.alternativeTitles?.map(\.title).filter { !$0.isEmpty } ?? [],
            synopsis: row.summary ?? "",
            url: descriptor.baseURL.appendingPathComponent("series").appendingPathComponent(
                String(row.id)),
            classification: Self.classification(for: row),
            publication: Self.publication(row.status),
            covers: [Self.cover(row.cover)].compactMap { $0 },
            tags: row.tags.compactMap { Self.names[$0] },
            authors: ((row.author ?? []) + (row.artist ?? [])).filter { !$0.isEmpty }
        )
    }

    // whichever signal is stronger. neither can clear a series alone - the rating
    // is unset on almost the whole catalogue, and an empty tag list is silence
    // rather than a clean bill - so an untagged, unrated series stays unknown
    private static func classification(for row: SeriesDTO) -> Classification {
        let tags = Set(row.tags)
        let rating = row.contentRating ?? 1

        if rating >= 3 || !adult.isDisjoint(with: tags) { return .Explicit }
        if rating == 2 || !suggestive.isDisjoint(with: tags) { return .Suggestive }
        return tags.isEmpty ? .Unknown : .Safe
    }

    // seven of theirs onto five of ours. Dropped and Cancelled are the same thing
    // to a reader, as are Paused and Hiatus. Upcoming has no equivalent and is
    // not offered as a filter either
    private static func publication(_ status: Int?) -> Publication {
        switch status {
        case 1: .Ongoing
        case 2: .Completed
        case 3, 6: .Hiatus
        case 4, 7: .Cancelled
        default: .Unknown
        }
    }
}

// MARK: - Chapters

extension ScansGGSource {
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        // unpaginated and across every group, which is what our scanlator
        // priority wants - the site itself shows one group at a time
        async let rowsTask: [ChapterDTO] = get(
            "chapters", [.init(name: "series_id", value: seriesSlug)])
        // the rows carry group_id and no name, and group_details=true is a no-op
        // on this route, so the names need their own request
        async let groupsTask: [GroupDTO] = get("groups", [])

        let (rows, groups) = try await (rowsTask, groupsTask)
        let names = Dictionary(
            groups.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        return rows.map { row in
            ChapterEntry(
                slug: String(row.id),
                title: row.title ?? "",
                number: row.number ?? 0,
                language: row.language.flatMap(LanguageCode.init) ?? .english,
                scanlator: row.groupID.flatMap { names[$0] } ?? descriptor.name,
                url: descriptor.baseURL
                    .appendingPathComponent("series")
                    .appendingPathComponent(seriesSlug)
                    .appendingPathComponent(String(row.id)),
                publishedDate: Self.date(from: row.createdAt)
            )
        }
    }
}

// MARK: - Content

extension ScansGGSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        let response: NavigationDTO = try await get(
            "chapter-navigation",
            [
                .init(name: "series_id", value: seriesSlug),
                .init(name: "chapter_id", value: chapterSlug),
            ])

        // position is already zero-based, but it is the sort key rather than the
        // array order, so it decides both
        return response.chapter.pages
            .sorted { $0.position < $1.position }
            .enumerated()
            .compactMap { index, page in
                guard let url = Self.page(chapter: chapterSlug, path: page.path) else { return nil }
                return PageURL(index: index, url: url)
            }
    }
}

// MARK: - Requests

extension ScansGGSource {
    private func get<Model: Decodable & Sendable>(_ path: String, _ items: [URLQueryItem])
        async throws -> Model
    {
        var components = URLComponents(
            url: Self.api.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items.isEmpty ? nil : items

        guard let url = components.url else { throw URLError(.badURL) }

        let envelope: Envelope<Model> = try await network.get(
            url: url,
            headers: ["Referer": descriptor.referer.absoluteString]
        )

        return envelope.data
    }

    private static func cover(_ file: String?) -> URL? {
        guard let file, !file.isEmpty else { return nil }
        return cdn.appendingPathComponent("covers").appendingPathComponent(file)
    }

    private static func page(chapter: String, path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        return cdn.appendingPathComponent("pages").appendingPathComponent(chapter)
            .appendingPathComponent(path)
    }

    // "2026-05-03 17:31:46", no zone marker, and the site reads it as utc. parsed
    // here rather than by the shared decoder, whose strategy expects iso8601 and
    // would fail the whole response on the first timestamp
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func date(from value: String?) -> Date {
        guard let value else { return .distantPast }
        return formatter.date(from: value) ?? .distantPast
    }
}

// MARK: - DTOs

extension ScansGGSource {
    // a miss is a 200 carrying `"data": false` rather than a status code, so the
    // decode of `data` is what fails and that failure IS the miss. left to throw
    // rather than caught and re-thrown - NetworkError.decoding already says it
    private struct Envelope<Model: Decodable & Sendable>: Decodable, Sendable {
        let data: Model
    }

    struct SeriesDTO: Decodable, Sendable {
        let id: Int
        let title: String
        let cover: String?
        let summary: String?
        let type: Int?
        let status: Int?
        let contentRating: Int?
        let tags: [Int]
        let author: [String]?
        let artist: [String]?
        let alternativeTitles: [AltTitleDTO]?

        private enum CodingKeys: String, CodingKey {
            case id, title, cover, summary, type, status, tags, author, artist
            case contentRating = "content_rating"
            case alternativeTitles = "alternative_titles"
        }
    }

    struct AltTitleDTO: Decodable, Sendable {
        let title: String
    }

    struct ChapterDTO: Decodable, Sendable {
        let id: Int
        let groupID: Int?
        let number: Double?
        let title: String?
        let language: String?
        let createdAt: String?

        private enum CodingKeys: String, CodingKey {
            case id, number, title, language
            case groupID = "group_id"
            case createdAt = "created_at"
        }
    }

    struct GroupDTO: Decodable, Sendable {
        let id: Int
        let title: String
    }

    struct NavigationDTO: Decodable, Sendable {
        let chapter: ChapterContentDTO
    }

    struct ChapterContentDTO: Decodable, Sendable {
        let pages: [PageDTO]
    }

    struct PageDTO: Decodable, Sendable {
        let position: Int
        let path: String
    }
}

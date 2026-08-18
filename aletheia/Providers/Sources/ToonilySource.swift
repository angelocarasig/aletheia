//
//  ToonilySource.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import SwiftSoup

// madara wordpress theme behind cloudflare: every content call is server-rendered
// html (the admin-ajax "api" returns rendered fragments, not json), so this is a
// SwiftSoup scrape riding the auth layer. shapes documented and verify-gated in
// docs/sources/toonily.md
struct ToonilySource: SourceService, AuthenticatingSource {
    let requester: AuthRequester

    private static let seriesPath = "serie"
    private static let matureCookie = "toonily-mature=1"

    private enum Selector {
        static let card = "div.page-item-detail.manga"
        static let cardLink = "div.post-title a"
        static let noResults = ".no-posts"
        static let title = "div.post-title h3, div.post-title h1, #manga-title > h1"
        static let synopsis = "div.content-area div.summary__content"
        static let author = "div.author-content > a"
        static let artist = "div.artist-content > a"
        static let status = "div.summary-content"
        static let genres = "div.genres-content a"
        static let cover = "div.summary_image img"
        static let chapterRow = "li.wp-manga-chapter"
        static let chapterDate = "span.chapter-release-date"
        static let pageImage =
            "div.page-break img, li.blocks-gallery-item img, .reading-content .text-left:not(:has(.blocks-gallery-item)) img"
        static let protector = "#chapter-protector-data"
    }

    let descriptor = SourceDescriptor(
        slug: "toonily",
        name: "Toonily",
        description:
            "Read Korean webtoons and manhwa online in English. Romance, drama and action titles updated daily.",
        icon: .toonily,
        languages: [.english],
        baseURL: URL(string: "https://toonily.com")!,
        referer: URL(string: "https://toonily.com")!,
        supportedFilters: [
            .text(id: "author", name: "Writer"),
            .text(id: "artist", name: "Artist"),
            // the 30 slugs the site's own search form exposes, verbatim - the
            // taxonomy holds ~55 terms but the raunchier ones are deliberately
            // absent from their ui, and we declare only what their client sends.
            // mature is this site's adult catch-all, so ticking it opens the gate
            .multiSelect(
                id: "genre",
                name: "Genres",
                options: [
                    .init(id: "action", name: "Action"),
                    .init(id: "adventure", name: "Adventure"),
                    .init(id: "comedy", name: "Comedy"),
                    .init(id: "crime", name: "Crime"),
                    .init(id: "drama", name: "Drama"),
                    .init(id: "fantasy", name: "Fantasy"),
                    .init(id: "gossip", name: "Gossip"),
                    .init(id: "historical", name: "Historical"),
                    .init(id: "horror", name: "Horror"),
                    .init(id: "isekai", name: "Isekai"),
                    .init(id: "josei", name: "Josei"),
                    .init(id: "magic", name: "Magic"),
                    .init(id: "mature", name: "Mature", sensitivity: .adult),
                    .init(id: "mystery", name: "Mystery"),
                    .init(id: "psychological", name: "Psychological"),
                    .init(id: "romance", name: "Romance"),
                    .init(id: "school-life", name: "School Life"),
                    .init(id: "scifi-webtoon", name: "Sci-Fi"),
                    .init(id: "seinen", name: "Seinen"),
                    .init(id: "shoujo", name: "Shoujo"),
                    .init(id: "shounen", name: "Shounen"),
                    .init(id: "slice-of-life", name: "Slice of Life"),
                    .init(id: "sports", name: "Sports"),
                    .init(id: "supernatural", name: "Supernatural"),
                    .init(id: "thriller", name: "Thriller"),
                    .init(id: "tragedy", name: "Tragedy"),
                    .init(id: "villainess", name: "Villainess"),
                    .init(id: "wuxia", name: "Wuxia"),
                    .init(id: "yaoi", name: "Yaoi", sensitivity: .suggestive),
                    .init(id: "yuri", name: "Yuri"),
                ],
                canExclude: false
            ),
            .select(
                id: "op",
                name: "Genre Inclusion",
                options: [
                    .init(id: "any", name: "Any"),
                    .init(id: "all", name: "All"),
                ]
            ),
            .multiSelect(
                id: "status",
                name: "Status",
                options: [
                    .init(id: "on-going", name: "Ongoing"),
                    .init(id: "end", name: "Completed"),
                    .init(id: "on-hold", name: "Hiatus"),
                    .init(id: "canceled", name: "Cancelled"),
                ],
                canExclude: false
            ),
            // the tri-state gate from docs/sources/toonily.md §2c: absent means the
            // request actively excludes adult content; either marked option opens
            // the gate and every stub in the response inherits the stamp
            .select(
                id: "mature",
                name: "Mature Content",
                options: [
                    .init(id: "included", name: "Included", sensitivity: .adult),
                    .init(id: "only", name: "Only", sensitivity: .adult),
                ]
            ),
        ],
        // option ids are the site's own m_orderby values, which its order-by tab
        // bar composes with s and every filter - verified from the live markup
        supportedSort: .init(
            options: [
                .init(id: "relevance", name: "Best match"),
                .init(id: "latest", name: "Latest update"),
                .init(id: "new-manga", name: "Recently added"),
                .init(id: "alphabet", name: "Title (A-Z)"),
                .init(id: "rating", name: "Top rated"),
                .init(id: "trending", name: "Trending"),
                .init(id: "views", name: "Most viewed"),
            ],
            defaultSort: "relevance"
        )
    )

    var presets: [SourcePreset] {
        [
            .init(
                id: "latest", name: "Latest Updates", subtitle: "Freshly released chapters",
                order: 0,
                sort: .init(optionID: "latest")),
            .init(
                id: "new", name: "Recently Added", subtitle: "New series on Toonily", order: 1,
                sort: .init(optionID: "new-manga")),
            .init(
                id: "rating", name: "Top Rated", subtitle: "Highest rated by readers", order: 2,
                sort: .init(optionID: "rating")),
            .init(
                id: "popular", name: "Most Viewed", subtitle: "Most read of all time", order: 3,
                sort: .init(optionID: "views")),
            .init(
                id: "trending", name: "Trending This Week", subtitle: "Hot in the last seven days",
                order: 4,
                sort: .init(optionID: "trending")),
        ]
    }

    // the root serves the cloudflare interstitial to a plain request, which would
    // read as down - robots.txt is the one route the edge serves unchallenged
    var pingURL: URL { descriptor.baseURL.appendingPathComponent("robots.txt") }

    var specification: AuthSpecification {
        AuthSpecification(
            requirements: [.cookie(name: "cf_clearance")],
            challengeURL: descriptor.baseURL,
            userAgent: nil,
            maneuver: "Complete the check if one appears. This window closes automatically.",
            interactive: true
        )
    }
}

// MARK: - Requests

extension ToonilySource {
    private func request(_ url: URL, method: String = "GET", body: Data? = nil, mature: Bool)
        -> URLRequest
    {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(descriptor.referer.absoluteString, forHTTPHeaderField: "Referer")
        if let body {
            request.httpBody = body
            request.setValue(
                "application/x-www-form-urlencoded; charset=UTF-8",
                forHTTPHeaderField: "Content-Type")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        // request-scoped, never in the credential: search sends it only when the
        // gate is open, everything after search sends it always - an adult title
        // the reader owns must keep resolving whatever the current search gate says
        if mature {
            request.setValue(Self.matureCookie, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func seriesURL(_ slug: String) -> URL {
        descriptor.baseURL
            .appendingPathComponent(Self.seriesPath)
            .appendingPathComponent(slug)
    }
}

// MARK: - Search

extension ToonilySource {
    // one transport: the site's own GET search form, every parameter - filters,
    // m_orderby, adult - server-tested by their client. presets are plain sort
    // presets riding the same path
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let gateOpen = allowsAdult(for: query)
        let (data, _) = try await requester.send(
            request(searchURL(for: query, gateOpen: gateOpen), mature: gateOpen), for: self)

        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        let stubs = try Self.stubs(from: document, adult: gateOpen)

        // no total anywhere - the fragment ends with a .no-posts marker instead
        let noPosts = try !document.select(Selector.noResults).isEmpty()
        let exhausted = stubs.isEmpty || noPosts
        return SearchPage(items: stubs, next: exhausted ? nil : query.page + 1)
    }

    // GET /?s=...&post_type=wp-manga - the search-advanced-form, parameter for
    // parameter. pagination is wordpress's /page/N/ prefix
    private func searchURL(for query: SearchQuery, gateOpen: Bool) -> URL {
        var items: [URLQueryItem] = [
            .init(name: "post_type", value: "wp-manga"),
            .init(name: "s", value: Self.sanitized(query.text)),
        ]

        let sort = resolvedSort(for: query)
        if sort.optionID != "relevance" {
            items.append(.init(name: "m_orderby", value: sort.optionID))
        }

        for filter in query.filters {
            switch filter {
            case .text(let id, let value) where !value.isEmpty:
                items.append(.init(name: id, value: value))
            case .multiSelect(let id, let included, _) where id == "genre":
                items.append(contentsOf: included.map { .init(name: "genre[]", value: $0) })
            case .multiSelect(let id, let included, _) where id == "status":
                items.append(contentsOf: included.map { .init(name: "status[]", value: $0) })
            case .select(_, "all") where filter.id == "op":
                items.append(.init(name: "op", value: "1"))
            default:
                break
            }
        }

        // the form's own radio: "" all content, 0 family friendly, 1 mature only.
        // any adult-marked tick (the mature select or the mature genre) opens to
        // all - only the explicit Only narrows to 1
        let adult: String =
            switch query.filters.first(where: { $0.id == "mature" }) {
            case .select(_, "only"): "1"
            case .select(_, "included"): ""
            default: gateOpen ? "" : "0"
            }
        items.append(.init(name: "adult", value: adult))

        var base = descriptor.baseURL
        if query.page > 1 {
            base = base.appendingPathComponent("page").appendingPathComponent(String(query.page))
        }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        return components.url!
    }

    private static func stubs(from document: Document, adult: Bool) throws -> [SeriesStub] {
        try document.select(Selector.card).compactMap { card -> SeriesStub? in
            guard let link = try card.select(Selector.cardLink).first() else { return nil }

            let href = try link.attr("href")
            guard let slug = slug(from: href) else { return nil }

            let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let cover = try card.select("img").first().flatMap { try imageURL(from: $0) }

            return SeriesStub(
                slug: slug,
                title: title,
                cover: cover.map(fullResolution),
                adult: adult
            )
        }
    }

    // /serie/<slug>/ today, /webtoon/<slug>/ before the apr-2025 redesign - old
    // links still circulate, so both path markers resolve
    private static func slug(from href: String) -> String? {
        let parts = href.split(separator: "/")
        for marker in [Substring(seriesPath), "webtoon"] {
            if let index = parts.firstIndex(of: marker), parts.index(after: index) < parts.endIndex
            {
                return String(parts[parts.index(after: index)])
            }
        }
        return nil
    }

    // their search chokes on punctuation, so the maintained implementations strip
    // to lowercase alphanumerics before sending
    private static func sanitized(_ text: String?) -> String {
        (text ?? "")
            .lowercased()
            .replacing(/[^a-z0-9]+/, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Details

extension ToonilySource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let url = seriesURL(seriesSlug)
        let (data, response) = try await requester.send(request(url, mature: true), for: self)
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

        let title = try document.select(Selector.title).first()?.text() ?? ""
        let synopsis = try document.select(Selector.synopsis).first()?.text() ?? ""
        let authors = try
            (document.select(Selector.author).map { try $0.text() }
            + document.select(Selector.artist).map { try $0.text() })
            .filter { !$0.isEmpty }

        let cover = try document.select(Selector.cover).first().flatMap {
            try Self.imageURL(from: $0)
        }
        let tags = try document.select(Selector.genres).map { try $0.text() }.filter { !$0.isEmpty }

        // the site 301s legacy /webtoon/ paths, so the canonical slug is whatever
        // the response url carries - the duplicate guard checks both
        let canonical = response.url.flatMap { Self.slug(from: $0.path) } ?? seriesSlug

        return SeriesDetail(
            slug: canonical,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            altTitles: [],
            synopsis: synopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url,
            classification: Self.classification(tags: tags),
            publication: try Self.publication(of: document),
            covers: [cover.map(Self.fullResolution)].compactMap { $0 },
            tags: tags,
            authors: authors
        )
    }

    // the stock madara 18+ overlay was removed for the site-wide family-mode
    // toggle, so genres are the per-title signal - Mature is this site's adult
    // catch-all (its genre archive collapses to near-empty under family mode)
    private static func classification(tags: [String]) -> Classification {
        let adult = tags.contains { tag in
            let lowered = tag.lowercased()
            return lowered.contains("mature") || lowered.contains("adult")
        }
        return adult ? .Explicit : .Safe
    }

    private static func publication(of document: Document) throws -> Publication {
        let texts = try document.select(Selector.status).map { try $0.text().lowercased() }
        for text in texts {
            if text.contains("ongoing") { return .Ongoing }
            if text.contains("complet") || text.contains("end") { return .Completed }
            if text.contains("hiatus") || text.contains("hold") { return .Hiatus }
            if text.contains("cancel") { return .Cancelled }
        }
        return .Unknown
    }
}

// MARK: - Chapters

extension ToonilySource {
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        let url = seriesURL(seriesSlug).appendingPathComponent("ajax/chapters")
        let (data, _) = try await requester.send(
            request(url, method: "POST", body: Data(), mature: true), for: self)
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

        return try document.select(Selector.chapterRow).compactMap { row -> ChapterEntry? in
            guard let link = try row.select("a").first() else { return nil }

            let href = try link.attr("href")
            guard let slug = href.split(separator: "/").last.map(String.init), !slug.isEmpty else {
                return nil
            }

            let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let date = try row.select(Selector.chapterDate).first()?.text()

            return ChapterEntry(
                slug: slug,
                title: title,
                number: Self.number(from: title),
                language: .english,
                // no group attribution anywhere on the site, and this keys the
                // scanlator priority rows, so it has to be stable across fetches
                scanlator: descriptor.name,
                url: seriesURL(seriesSlug).appendingPathComponent(slug),
                publishedDate: Self.date(from: date)
            )
        }
    }

    // labels read "Chapter 179" / "Chapter 179.5"
    private static func number(from label: String) -> Double {
        let digits = label.reversed().prefix { $0.isNumber || $0 == "." }
        return Double(String(digits.reversed())) ?? 0
    }

    private static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yy"
        return formatter
    }()

    private static let absoluteLong: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    // "Aug 8, 25", "August 8, 2025", "2 days ago", "UP" (a badge meaning today).
    // unparseable dates fall to .distantPast rather than failing the list
    private static func date(from value: String?) -> Date {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else {
            return .distantPast
        }

        if value.contains("UP") || value.lowercased().contains("today") {
            return .now
        }
        if value.lowercased().contains("yesterday") {
            return .now.addingTimeInterval(-86_400)
        }
        if let parsed = absolute.date(from: value) ?? absoluteLong.date(from: value) {
            return parsed
        }
        return relative(from: value.lowercased()) ?? .distantPast
    }

    private static func relative(from value: String) -> Date? {
        guard value.contains("ago"),
            let match = value.firstMatch(of: /(\d+)\s*(min|hour|day|week|month|year)/)
        else { return nil }

        guard let count = Double(match.1) else { return nil }
        let unit: TimeInterval =
            switch match.2 {
            case "min": 60
            case "hour": 3_600
            case "day": 86_400
            case "week": 604_800
            case "month": 2_592_000
            default: 31_536_000
            }
        return .now.addingTimeInterval(-count * unit)
    }
}

// MARK: - Content

extension ToonilySource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        // ?style=list forces the long-strip markup; without it madara may
        // paginate the reader one image per page
        var components = URLComponents(
            url: seriesURL(seriesSlug).appendingPathComponent(chapterSlug),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [.init(name: "style", value: "list")]

        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await requester.send(request(url, mature: true), for: self)
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

        // madara's optional aes page wrapper - never observed on toonily, so its
        // appearance is a parse failure to surface, not content to silently drop
        guard try document.select(Selector.protector).isEmpty() else {
            throw URLError(.cannotParseResponse)
        }

        // no dimensions anywhere on this site - tier 2 in-band extraction fills
        // them during the real download
        return try document.select(Selector.pageImage).enumerated().compactMap { index, image in
            try Self.imageURL(from: image).map { PageURL(index: index, url: $0) }
        }
    }
}

// MARK: - Images

extension ToonilySource {
    // lazy-loading moves the real url through a parade of attributes; src is the
    // last resort because it usually holds the placeholder
    private static func imageURL(from element: Element) throws -> URL? {
        for attribute in ["data-src", "data-lazy-src", "data-cfsrc", "data-manga-src", "src"] {
            let value = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, let url = URL(string: value) { return url }
        }
        return nil
    }

    // listing covers are downsized variants with a -WxH filename suffix on the
    // static cdn; stripping it addresses the full-resolution original
    private static func fullResolution(_ url: URL) -> URL {
        let string = url.absoluteString
        guard let match = string.firstMatch(of: /-\d+x\d+(?=\.\w+$)/) else { return url }
        var stripped = string
        stripped.removeSubrange(match.range)
        return URL(string: stripped) ?? url
    }
}

//
//  WeebCentralSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import SwiftSoup

// htmx site: the search page's form immediately swaps in /search/data's fragment, so requesting that endpoint directly skips the shell
struct WeebCentralSource: SourceService {
    let network: NetworkConfiguration

    // the fragment always returns 32 and ignores limit, so paging is offset-only
    private static let window = 32
    private static let display = "Full Display"

    private enum Selector {
        static let card = "article.bg-base-300"
        static let title = "a.line-clamp-1"
        static let cover = "img"
    }

    let descriptor = SourceDescriptor(
        slug: "weebcentral",
        name: "WeebCentral",
        description:
            "Explore Weeb Central for top manga titles, hidden gems, and the latest releases. Join our community of manga enthusiasts!",
        icon: .weebCentral,
        languages: [.english],
        baseURL: URL(string: "https://weebcentral.com")!,
        referer: URL(string: "https://weebcentral.com")!,
        supportedFilters: [
            .multiSelect(
                id: "included_status",
                name: "Status",
                options: [
                    .init(id: "Ongoing", name: "Ongoing"),
                    .init(id: "Complete", name: "Complete"),
                    .init(id: "Hiatus", name: "Hiatus"),
                    .init(id: "Canceled", name: "Cancelled"),
                ],
                canExclude: false
            ),
            .multiSelect(
                id: "included_type",
                name: "Type",
                options: [
                    .init(id: "Manga", name: "Manga"),
                    .init(id: "Manhwa", name: "Manhwa"),
                    .init(id: "Manhua", name: "Manhua"),
                    .init(id: "OEL", name: "OEL"),
                ],
                canExclude: false
            ),
            // v2 declared these include-only, but excluded_tag demonstrably filters too - verified against live results
            .multiSelect(
                id: "included_tag",
                name: "Tags",
                options: [
                    .init(id: "Action", name: "Action"),
                    .init(id: "Adult", name: "Adult", sensitivity: .suggestive),
                    .init(id: "Adventure", name: "Adventure"),
                    .init(id: "Comedy", name: "Comedy"),
                    .init(id: "Doujinshi", name: "Doujinshi"),
                    .init(id: "Drama", name: "Drama"),
                    .init(id: "Ecchi", name: "Ecchi", sensitivity: .suggestive),
                    .init(id: "Fantasy", name: "Fantasy"),
                    .init(id: "Gender Bender", name: "Gender Bender"),
                    .init(id: "Harem", name: "Harem"),
                    .init(id: "Hentai", name: "Hentai", sensitivity: .adult),
                    .init(id: "Historical", name: "Historical"),
                    .init(id: "Horror", name: "Horror"),
                    .init(id: "Isekai", name: "Isekai"),
                    .init(id: "Josei", name: "Josei"),
                    .init(id: "Lolicon", name: "Lolicon", sensitivity: .suggestive),
                    .init(id: "Martial Arts", name: "Martial Arts"),
                    .init(id: "Mature", name: "Mature", sensitivity: .suggestive),
                    .init(id: "Mecha", name: "Mecha"),
                    .init(id: "Mystery", name: "Mystery"),
                    .init(id: "Other", name: "Other"),
                    .init(id: "Psychological", name: "Psychological"),
                    .init(id: "Romance", name: "Romance"),
                    .init(id: "School Life", name: "School Life"),
                    .init(id: "Sci-fi", name: "Sci-fi"),
                    .init(id: "Seinen", name: "Seinen"),
                    .init(id: "Shotacon", name: "Shotacon", sensitivity: .suggestive),
                    .init(id: "Shoujo", name: "Shoujo"),
                    .init(id: "Shoujo Ai", name: "Shoujo Ai"),
                    .init(id: "Shounen", name: "Shounen"),
                    .init(id: "Shounen Ai", name: "Shounen Ai"),
                    .init(id: "Slice of Life", name: "Slice of Life"),
                    .init(id: "Smut", name: "Smut", sensitivity: .suggestive),
                    .init(id: "Sports", name: "Sports"),
                    .init(id: "Supernatural", name: "Supernatural"),
                    .init(id: "Tragedy", name: "Tragedy"),
                    .init(id: "Yaoi", name: "Yaoi", sensitivity: .suggestive),
                    .init(id: "Yuri", name: "Yuri"),
                ],
                canExclude: true
            ),
            .select(
                id: "official",
                name: "Official Release",
                options: [
                    .init(id: "Any", name: "Any"),
                    .init(id: "True", name: "Official only"),
                    .init(id: "False", name: "Scanlations only"),
                ]
            ),
            .select(
                id: "anime",
                name: "Has Anime",
                options: [
                    .init(id: "Any", name: "Any"),
                    .init(id: "True", name: "Adapted"),
                    .init(id: "False", name: "Not adapted"),
                ]
            ),
            // binary on purpose - Any would return a mixed set with no per-result adult signal in the fragment, so dropping it keeps the stamp exact
            .select(
                id: "adult",
                name: "Adult Content",
                options: [
                    .init(id: "False", name: "Exclude"),
                    .init(id: "True", name: "Include only", sensitivity: .adult),
                ]
            ),
        ],
        // api takes sort and order as two params but an option id IS a direction here, so the id carries both and the source splits it
        supportedSort: .init(
            options: [
                .init(id: "Best Match", name: "Best match"),
                .init(id: "Popularity", name: "Popularity"),
                .init(id: "Subscribers", name: "Subscribers"),
                .init(id: "Latest Updates", name: "Latest updates"),
                .init(id: "Recently Added", name: "Recently added"),
                .init(id: "Recently Added|Ascending", name: "Oldest added"),
                .init(id: "Alphabet|Ascending", name: "Title (A-Z)"),
                .init(id: "Alphabet", name: "Title (Z-A)"),
            ],
            defaultSort: "Best Match"
        )
    )

    var presets: [SourcePreset] {
        [
            .init(
                id: "popular", name: "Popular", subtitle: "Most read on WeebCentral", order: 0,
                sort: .init(optionID: "Popularity")),
            .init(
                id: "latest", name: "Latest Updates", subtitle: "Freshly released chapters",
                order: 1,
                sort: .init(optionID: "Latest Updates")),
            .init(
                id: "new", name: "New Releases", subtitle: "Recently added series", order: 2,
                sort: .init(optionID: "Recently Added")),
            .init(
                id: "subscribed", name: "Most Followed",
                subtitle: "Series with the most subscribers", order: 3,
                sort: .init(optionID: "Subscribers")),
        ]
    }
}

// MARK: - Search

extension WeebCentralSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        var items: [URLQueryItem] = [
            .init(name: "display_mode", value: Self.display),
            .init(name: "offset", value: String(max(0, query.page - 1) * Self.window)),
        ]

        if let text = query.text, !text.isEmpty {
            items.append(.init(name: "text", value: text))
        }

        let sort = resolvedSort(for: query)
        let (field, order) = Self.split(sort.optionID)
        items.append(.init(name: "sort", value: field))
        items.append(.init(name: "order", value: order))

        items += Self.parameters(for: query.filters)
        items += Self.defaults(missing: query.filters)
        items += Self.adultDefault(missing: query.filters)

        var components = URLComponents(
            url: descriptor.baseURL.appendingPathComponent("search/data"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items

        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await network.get(
            url: url, headers: ["Referer": descriptor.referer.absoluteString])
        let stubs = try Self.stubs(
            from: String(decoding: data, as: UTF8.self),
            adult: allowsAdult(for: query))

        // no total comes back, so a full window is the only sign there is more
        return SearchPage(items: stubs, next: stubs.count == Self.window ? query.page + 1 : nil)
    }

    private static func stubs(from html: String, adult: Bool) throws -> [SeriesStub] {
        let document = try SwiftSoup.parse(html)

        return try document.select(Selector.card).compactMap { card -> SeriesStub? in
            guard let link = try card.select(Selector.title).first() else { return nil }

            let href = try link.attr("href")
            guard let slug = identifier(from: href) else { return nil }

            let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            return SeriesStub(
                slug: slug,
                title: title,
                cover: cover(for: slug),
                adult: adult
            )
        }
    }

    // keyed by the ulid on a cdn - no img element to select, nothing breaks when markup is restyled
    private static func cover(for slug: String) -> URL? {
        URL(string: "https://temp.compsci88.com/cover/normal/\(slug).webp")
    }

    // suffix-anchored so a legitimate pipe inside a title survives - only a
    // trailing "| Weeb Central" is branding
    static func strippingSiteSuffix(_ title: String) -> String {
        title
            .replacing(/\s*\|\s*Weeb\s?Central\s*$/.ignoresCase(), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // /series/{ULID}/{title-slug} - the ulid identifies the series, the trailing slug is decorative
    private static func identifier(from href: String) -> String? {
        let parts = href.split(separator: "/")
        guard let index = parts.firstIndex(of: "series"), parts.index(after: index) < parts.endIndex
        else {
            return nil
        }
        return String(parts[parts.index(after: index)])
    }
}

// MARK: - Details

// the only method without an endpoint behind it - metadata is rendered into the page, not swapped in by htmx, so there is no fragment to ask for
extension WeebCentralSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let url = descriptor.baseURL
            .appendingPathComponent("series")
            .appendingPathComponent(seriesSlug)

        let data = try await network.get(
            url: url, headers: ["Referer": descriptor.referer.absoluteString])
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

        // two h1s carry the same title, one per breakpoint; og:title arrives branded ("Blue Lock | Weeb Central") - either path needs the suffix stripped
        let heading = try document.select("h1").first()?.text() ?? ""
        let raw = try document.select("meta[property=og:title]").first()?.attr("content") ?? heading
        let title = Self.strippingSiteSuffix(raw)

        let synopsis = try document.select("p.whitespace-pre-wrap").first()?.text() ?? ""

        return SeriesDetail(
            slug: seriesSlug,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            altTitles: try Self.associated(in: document),
            synopsis: synopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url,
            classification: Self.classification(try Self.values(in: document, for: "adult").first),
            publication: Self.publication(
                try Self.values(in: document, for: "included_status").first),
            covers: [Self.cover(for: seriesSlug)].compactMap { $0 },
            tags: try Self.values(in: document, for: "included_tag"),
            authors: try Self.values(in: document, for: "author")
        )
    }

    // read from the href's query, not the link text, so display wording can change without breaking anything - same vocabulary search() depends on
    private static func values(in document: Document, for key: String) throws -> [String] {
        try document.select("a[href*=\(key)=]").compactMap { link in
            let href = try link.attr("href")
            guard
                let components = URLComponents(string: href),
                let value = components.queryItems?.first(where: { $0.name == key })?.value,
                !value.isEmpty
            else { return nil }
            // site form-encodes spaces as "+", which URLComponents leaves literal - it only decodes percent escapes
            return value.replacingOccurrences(of: "+", with: " ")
        }
    }

    private static func associated(in document: Document) throws -> [String] {
        guard let label = try document.select("strong:contains(Associated Name)").first(),
            let list = try label.parent()?.select("ul").first()
        else { return [] }

        return try list.select("li").map {
            try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    // the site exposes a binary adult flag where others have four levels, so Suggestive is unreachable here
    private static func classification(_ adult: String?) -> Classification {
        switch adult {
        case "False": .Safe
        case "True": .Explicit
        default: .Unknown
        }
    }

    private static func publication(_ status: String?) -> Publication {
        switch status {
        case "Ongoing": .Ongoing
        case "Complete": .Completed
        case "Hiatus": .Hiatus
        case "Canceled": .Cancelled
        default: .Unknown
        }
    }
}

// MARK: - Chapters

extension WeebCentralSource {
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        let url = descriptor.baseURL
            .appendingPathComponent("series")
            .appendingPathComponent(seriesSlug)
            .appendingPathComponent("full-chapter-list")

        let data = try await network.get(
            url: url, headers: ["Referer": descriptor.referer.absoluteString])
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

        let rows = try document.select("a[href*=/chapters/]")

        // deliberately no count shortcut - the response is already in hand, and a matching count would pin any misparsed row to wrong values permanently
        return try rows.compactMap { row -> ChapterEntry? in
            let href = try row.attr("href")
            guard let slug = href.split(separator: "/").last.map(String.init), !slug.isEmpty else {
                return nil
            }

            // first span holds the badge image; the label is nested in the next - taking the first span with text, not the first span, is what stops every chapter parsing as "" and numbering 0
            let label =
                try row.select("span")
                .map { $0.ownText() }
                .first { !$0.isEmpty } ?? ""
            let published = try row.select("time[datetime]").first()?.attr("datetime")

            return ChapterEntry(
                slug: slug,
                title: label.trimmingCharacters(in: .whitespacesAndNewlines),
                number: Self.number(from: label),
                language: .english,
                // fragment carries no group attribution - this keys scanlator priority so it must stay stable across fetches
                scanlator: descriptor.name,
                url: descriptor.baseURL.appendingPathComponent("chapters").appendingPathComponent(
                    slug),
                publishedDate: Self.date(from: published)
            )
        }
    }

    // labels read "Chapter 85"
    private static func number(from label: String) -> Double {
        let digits = label.reversed().prefix { $0.isNumber || $0 == "." }
        return Double(String(digits.reversed())) ?? 0
    }

    // parsed here rather than by the shared decoder, whose strategy is tuned for other sources and would fail the whole response on one odd timestamp
    private static func date(from value: String?) -> Date {
        guard let value else { return .distantPast }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: value) { return parsed }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? .distantPast
    }
}

// MARK: - Content

extension WeebCentralSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        var components = URLComponents(
            url: descriptor.baseURL
                .appendingPathComponent("chapters")
                .appendingPathComponent(chapterSlug)
                .appendingPathComponent("images"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "is_prev", value: "False"),
            .init(name: "reading_style", value: "long_strip"),
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await network.get(
            url: url, headers: ["Referer": descriptor.referer.absoluteString])
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

        // already absolute on a separate host - the reader's referer modifier is what keeps them loading
        return try document.select("img[src]").enumerated().compactMap { index, image in
            guard let source = URL(string: try image.attr("src")) else { return nil }
            return PageURL(index: index, url: source)
        }
    }
}

// MARK: - Parameters

extension WeebCentralSource {
    // option id is `field` or `field|Ascending` - descending is default since every option but the two alphabetical ones wants it
    private static func split(_ optionID: String) -> (field: String, order: String) {
        let parts = optionID.components(separatedBy: "|")
        guard parts.count == 2 else { return (optionID, "Descending") }
        return (parts[0], parts[1])
    }

    private static func parameters(for filters: [FilterSelection]) -> [URLQueryItem] {
        filters.flatMap { filter -> [URLQueryItem] in
            switch filter {
            // ids are already the request's own parameter names - excluded side is the same name with the prefix swapped
            case .multiSelect(let id, let included, let excluded) where !excluded.isEmpty:
                let opposite = id.replacingOccurrences(of: "included_", with: "excluded_")
                return included.map { .init(name: id, value: $0) }
                    + excluded.map { .init(name: opposite, value: $0) }

            case .multiSelect(let id, let included, _):
                return included.map { .init(name: id, value: $0) }
            case .select(let id, let optionID):
                return [.init(name: id, value: optionID)]
            case .text(let id, let value):
                return value.isEmpty ? [] : [.init(name: id, value: value)]
            case .number(let id, let value):
                return [.init(name: id, value: String(value))]
            }
        }
    }

    // the three tri-state filters must be present even when untouched - the form always submits them, omitting them narrows results
    private static func defaults(missing filters: [FilterSelection]) -> [URLQueryItem] {
        let chosen = Set(filters.map(\.id))
        // adult excluded here: Any means "unset" for the other two, but on this axis it means "return both kinds" - the gate must exclude, not stay quiet (see adultDefault)
        return ["official", "anime"]
            .filter { !chosen.contains($0) }
            .map { .init(name: $0, value: "Any") }
    }

    // the flag is theirs, not ours - drawn wide enough to cover Berserk, so Exclude hides mature seinen this app wouldn't call adult; accepted for the simpler binary over excluded_tag=Hentai, which was measured narrower
    private static func adultDefault(missing filters: [FilterSelection]) -> [URLQueryItem] {
        guard !filters.contains(where: { $0.id == "adult" }) else { return [] }
        return [.init(name: "adult", value: "False")]
    }
}

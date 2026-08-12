//
//  MangaBallSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 11/8/2026.
//

import Foundation
import SwiftSoup

// an aggregator of aggregators: what its api calls a group is a rival site, and
// one chapter number routinely carries five to ten translations across mirrors
// and languages. two of the four calls are a form-encoded json api and two are
// scrapes, all four riding a php session paired with a csrf meta token.
// shapes and probes in docs/sources/mangaball.md
struct MangaBallSource: SourceService, AuthenticatingSource {
    let requester: AuthRequester

    private static let api = URL(string: "https://mangaball.net/api/v1")!

    // the word list the site's waf 403s on. a false positive on a sql-injection
    // rule, live since june and hit by ordinary titles - the litrpg genre is full
    // of them. plurals and embedded forms do not trigger, so they must survive
    // the normalising in `sanitized`
    private static let denied: Set<String> = ["system"]

    private enum Selector {
        static let title = "#comicDetail h6"
        static let altTitles = "#comicDetail div.alternate-name-container"
        static let cover = "img.featured-cover"
        static let synopsis = "#descriptionContent p"
        static let tags = "#comicDetail span[data-tag-id]"
        static let authors = "#comicDetail span[data-person-id]"
        static let status = "span.badge-status"
    }

    let descriptor = SourceDescriptor(
        slug: "mangaball",
        name: "MangaBall",
        description: "A vast aggregated library of manga, manhwa and manhua, gathered from two dozen scanlation sites and updated constantly.",
        icon: .mangaBall,
        languages: [.english, .chinese],
        baseURL: URL(string: "https://mangaball.net")!,
        referer: URL(string: "https://mangaball.net")!,
        supportedFilters: [
            .multiSelect(id: "tags", name: "Tags", options: Tag.options, canExclude: true),
            // the server default is `or` while the site's own ui always sends
            // `and`, so both modes go out explicitly on every request
            .select(
                id: "tag_included_mode",
                name: "Include Tags Matching",
                options: [
                    .init(id: "and", name: "All"),
                    .init(id: "or", name: "Any")
                ]
            ),
            .select(
                id: "tag_excluded_mode",
                name: "Exclude Tags Matching",
                options: [
                    .init(id: "and", name: "All"),
                    .init(id: "or", name: "Any")
                ]
            ),
            .select(
                id: "demographic",
                name: "Demographic",
                options: [
                    .init(id: "shounen", name: "Shounen"),
                    .init(id: "shoujo", name: "Shoujo"),
                    .init(id: "seinen", name: "Seinen"),
                    .init(id: "josei", name: "Josei"),
                    .init(id: "yuri", name: "Yuri", sensitivity: .suggestive)
                ]
            ),
            .select(
                id: "publicationStatus",
                name: "Status",
                options: [
                    .init(id: "ongoing", name: "Ongoing"),
                    .init(id: "completed", name: "Completed"),
                    .init(id: "hiatus", name: "Hiatus"),
                    .init(id: "cancelled", name: "Cancelled")
                ]
            ),
            // the site's own spellings: `jp` returns 63,482 titles where `ja`
            // returns none, and an unknown filter value returns zero results
            // rather than an error
            .select(
                id: "originalLanguages",
                name: "Original Language",
                options: [
                    .init(id: "en", name: "English"),
                    .init(id: "jp", name: "Japanese"),
                    .init(id: "kr", name: "Korean"),
                    .init(id: "zh", name: "Chinese")
                ]
            ),
            // carries no request parameter of its own. the gate here is a cookie
            // and the site marks no tag adult, so without a row to tick the gate
            // could only be opened by also narrowing to one adult tag
            .select(
                id: "adult",
                name: "Adult Content",
                options: [.init(id: "included", name: "Included", sensitivity: .adult)]
            )
        ],
        // nine of the twelve orderings the site offers. rating_desc and
        // rating_asc return the same order as each other, so rating is
        // unimplemented, and updated_at_desc is indistinguishable from the
        // default - probably is it. an unknown sort silently falls back
        supportedSort: .init(
            options: [
                .init(id: "updated_chapters_desc", name: "Latest Chapters"),
                .init(id: "updated_chapters_asc", name: "Longest Without a Chapter"),
                .init(id: "created_at_desc", name: "Recently Added"),
                .init(id: "created_at_asc", name: "Oldest Added"),
                .init(id: "name_asc", name: "Title (A-Z)"),
                .init(id: "name_desc", name: "Title (Z-A)"),
                .init(id: "views_desc", name: "Most Viewed"),
                .init(id: "views_asc", name: "Least Viewed"),
                .init(id: "updated_at_asc", name: "Least Recently Updated")
            ],
            defaultSort: "updated_chapters_desc"
        )
    )

    var presets: [SourcePreset] {
        [
            .init(id: "latest", name: "Latest Updates", subtitle: "Freshly released chapters", order: 0,
                  sort: .init(optionID: "updated_chapters_desc")),
            .init(id: "new", name: "Recently Added", subtitle: "New series in the library", order: 1,
                  sort: .init(optionID: "created_at_desc")),
            .init(id: "popular", name: "Most Viewed", subtitle: "Most read of all time", order: 2,
                  sort: .init(optionID: "views_desc")),
            .init(id: "alphabetical", name: "Browse A-Z", subtitle: "The whole catalogue by title", order: 3,
                  sort: .init(optionID: "name_asc"))
        ]
    }

    // every html route is ~100 KB and the api answers 403 without a credential,
    // so neither is a health check. robots.txt is the one cheap unguarded route
    var pingURL: URL { descriptor.baseURL.appendingPathComponent("robots.txt") }

    var specification: AuthSpecification {
        AuthSpecification(
            requirements: [
                .cookie(name: "PHPSESSID"),
                // this tenant serves no challenge today and may never mint one
                // even to a real browser, so waiting on it would time out every
                // capture. held and sent if a challenge ever starts issuing one
                .cookie(name: "cf_clearance", optional: true),
                .meta(name: "csrf-token", header: "X-CSRF-TOKEN")
            ],
            // a 302 sets the session but carries no body, so only a 200 html page
            // holds the token. the error page is the cheapest one that does
            challengeURL: descriptor.baseURL.appendingPathComponent("error/404"),
            userAgent: nil,
            maneuver: "Complete the check if one appears. This window closes automatically.",
            interactive: true
        )
    }

    // both a stale token and a waf block are 403 with a json body, and the
    // cloudflare default matches either (403 behind cloudflare), so the error
    // string decides. replaying a blocked body is a guaranteed second 403
    func isChallenge(response: HTTPURLResponse, body: Data) -> Bool {
        let text = String(decoding: body, as: UTF8.self)
        if text.contains("Malicious payload detected") { return false }
        if text.contains("CSRF token validation failed") { return true }
        return isCloudflareChallenge(response: response, body: body)
    }
}

// MARK: - Requests

extension MangaBallSource {
    // Accept-Encoding is deliberately not set: URLSession adds its own and
    // transparently inflates the reply, where a header we set makes the raw
    // compressed bytes our problem. it matters here - the chapter listing is
    // 406 KB raw against 31 KB on the wire, and 7.7 MB on a heavy series
    private func post(_ path: String, _ fields: [(String, String)], adult: Bool) -> URLRequest {
        var request = URLRequest(url: Self.api.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        Self.gate(&request, open: adult)
        return request
    }

    private func get(_ url: URL, adult: Bool = true) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(descriptor.referer.absoluteString, forHTTPHeaderField: "Referer")
        Self.gate(&request, open: adult)
        return request
    }

    // request-scoped, never in the credential: search sends it only when the gate
    // is open, everything after search sends it always - an adult title the
    // reader owns must keep resolving whatever the current search gate says.
    // the value is parsed as a boolean literal, so `=1` is silently ignored
    private static func gate(_ request: inout URLRequest, open: Bool) {
        guard open else { return }
        request.setValue("show18PlusContent=true", forHTTPHeaderField: "Cookie")
    }

    private static func form(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { field in
            let key = field.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? field.0
            let value = field.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? field.1
            return "\(key)=\(value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    private func seriesURL(_ slug: String) -> URL {
        // a bare id 302s to the error page and any prefix at all resolves to the
        // canonical path, so the slug stays the id and the prefix is filler
        URL(string: "\(descriptor.baseURL.absoluteString)/title-detail/series-\(slug)/")!
    }

    private func chapterURL(_ slug: String) -> URL {
        URL(string: "\(descriptor.baseURL.absoluteString)/chapter-detail/\(slug)/")!
    }
}

// MARK: - Search

extension MangaBallSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let gateOpen = allowsAdult(for: query)
        let text = query.text ?? ""

        var (data, response) = try await requester.send(
            post("title/search-advanced/", Self.fields(for: query, text: text), adult: gateOpen),
            for: self
        )

        if Self.isBlocked(status: response.statusCode, body: data) {
            let cleaned = Self.sanitized(text)
            // nothing came off, so the trigger is a word we do not know about.
            // retrying is guaranteed to fail again and an empty page would be
            // indistinguishable from an honest zero-result, which is how
            // coverage loss hides - so this says so loudly and gives up
            guard cleaned != text else {
                AppLog.shared.log(
                    "[mangaball] waf blocked \"\(text)\" and the denylist matched nothing - a new trigger word is live",
                    category: "source"
                )
                throw NetworkError.badResponse(status: response.statusCode, response: response)
            }
            // recovery says nothing to the reader: a warning on a query that did
            // return results reads as a hard failure
            (data, response) = try await requester.send(
                post("title/search-advanced/", Self.fields(for: query, text: cleaned), adult: gateOpen),
                for: self
            )
        }

        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.badResponse(status: response.statusCode, response: response)
        }

        let page = try JSONDecoder().decode(SearchResponse.self, from: data)
        let stubs = page.data.map { item in
            SeriesStub(
                slug: item.id,
                title: item.name,
                cover: item.cover.flatMap { URL(string: $0) },
                adult: item.adult ?? false
            )
        }

        let next = page.pagination.currentPage < page.pagination.lastPage
            ? page.pagination.currentPage + 1
            : nil
        return SearchPage(items: stubs, next: next)
    }

    // the three html fields the payload carries - alternateName, tags, authors -
    // feed nothing a stub holds, and the tag and author lists are truncated to
    // three anyway. the full sets come from details(), which is the scrape
    private static func fields(for query: SearchQuery, text: String) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("search_input", text),
            ("filters[page]", String(query.page)),
            ("filters[userSettingsEnabled]", "false")
        ]

        let sort = query.sort ?? SortSelection(optionID: "updated_chapters_desc")
        fields.append(("filters[sort]", sort.optionID))

        var includedMode = "and"
        var excludedMode = "and"

        for filter in query.filters {
            switch filter {
            case let .multiSelect(id, included, excluded) where id == "tags":
                fields.append(contentsOf: included.map { ("filters[tag_included_ids][]", $0) })
                fields.append(contentsOf: excluded.map { ("filters[tag_excluded_ids][]", $0) })
            case let .select(id, optionID) where id == "tag_included_mode":
                includedMode = optionID
            case let .select(id, optionID) where id == "tag_excluded_mode":
                excludedMode = optionID
            case let .select(id, optionID)
                where ["demographic", "publicationStatus", "originalLanguages"].contains(id):
                fields.append(("filters[\(id)]", optionID))
            default:
                break
            }
        }

        fields.append(("filters[tag_included_mode]", includedMode))
        fields.append(("filters[tag_excluded_mode]", excludedMode))
        return fields
    }

    private static func isBlocked(status: Int, body: Data) -> Bool {
        status == 403 && String(decoding: body, as: UTF8.self).contains("Malicious payload detected")
    }

    // tokens are normalised only to decide whether to drop them; whatever
    // survives goes out verbatim, so `systems` and `systemic` are untouched
    static func sanitized(_ text: String) -> String {
        let kept = text.split(separator: " ", omittingEmptySubsequences: true).filter { token in
            var word = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
            for possessive in ["'s", "\u{2019}s"] where word.hasSuffix(possessive) {
                word.removeLast(possessive.count)
            }
            return !denied.contains(word)
        }
        return kept.joined(separator: " ")
    }
}

// MARK: - Details

extension MangaBallSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let url = seriesURL(seriesSlug)
        let (data, response) = try await requester.send(get(url), for: self)
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

        let title = try document.select(Selector.title).first()?.text() ?? ""
        let synopsis = try document.select(Selector.synopsis).first()?.text() ?? ""
        let cover = try document.select(Selector.cover).first()?.attr("src")
        let tags = try Self.unique(document.select(Selector.tags).map { try $0.text() })
        let authors = try Self.unique(document.select(Selector.authors).map { try $0.text() })

        return SeriesDetail(
            // the id is the identity everywhere else, and the canonical path is
            // only ever a way of asking for it
            slug: seriesSlug,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            altTitles: try Self.altTitles(of: document),
            synopsis: synopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            url: response.url ?? url,
            classification: Self.classification(tags: tags),
            publication: try Self.publication(of: document),
            covers: [cover.flatMap { URL(string: $0) }].compactMap { $0 },
            tags: tags,
            authors: authors
        )
    }

    // the container's own text nodes are the titles, with muted slash spans
    // between them - reading them directly leaves the entities decoded and needs
    // no splitting on markup
    private static func altTitles(of document: Document) throws -> [String] {
        guard let container = try document.select(Selector.altTitles).first() else { return [] }
        let titles = container.getChildNodes()
            .compactMap { ($0 as? TextNode)?.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return unique(titles)
    }

    // the page carries no rating anywhere, so the tag set is the only signal.
    // unknown rather than safe: refresh always overwrites classification, so a
    // safe default would silently un-blur an adult series on its next refresh
    private static func classification(tags: [String]) -> Classification {
        let sensitivities = tags.compactMap { Tag.sensitivities[$0.lowercased()] }
        if sensitivities.contains(.adult) { return .Explicit }
        if sensitivities.contains(.suggestive) { return .Suggestive }
        return .Unknown
    }

    // the badge's class carries the value; its visible text is localisable, and
    // the same class name appears again inside a script template
    private static func publication(of document: Document) throws -> Publication {
        for badge in try document.select(Selector.status) {
            let classes = try badge.className()
            guard let match = classes.firstMatch(of: /status-([a-z]+)-title/) else { continue }
            return Publication(status: String(match.1))
        }
        return .Unknown
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

// MARK: - Chapters

extension MangaBallSource {
    // one unpaginated payload, and deliberately no `lang` narrowing: it drops the
    // chapter rows that exist only in other languages, which is exactly what
    // language priority exists to rank. TOTAL_CHAPTERS counts translations rather
    // than chapters and arrives attached to the payload it would let us skip, so
    // there is nothing here for RevalidatingSource either
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        let request = post(
            "chapter/chapter-listing-by-title-id/",
            [("title_id", seriesSlug), ("userSettingsEnabled", "false")],
            adult: true
        )
        let (data, _) = try await requester.send(request, for: self)
        let listing = try JSONDecoder().decode(ChapterListing.self, from: data)

        let numbers = listing.chapters.compactMap(\.number).filter { $0.isFinite && $0 >= 0 }
        let ceiling = Self.ceiling(for: numbers)

        return listing.chapters.flatMap { chapter -> [ChapterEntry] in
            guard let number = chapter.number, number.isFinite, number >= 0, number <= ceiling else { return [] }

            return chapter.translations.compactMap { translation -> ChapterEntry? in
                // a language we cannot render is dropped, never downgraded: the
                // usual `?? .english` fallback would relabel two thirds of this
                // source as english and hand the reader vietnamese
                guard let language = Self.language(translation.language) else { return nil }

                return ChapterEntry(
                    slug: translation.id,
                    title: translation.name ?? "",
                    number: number,
                    language: language,
                    scanlator: Self.scanlator(translation.group),
                    url: chapterURL(translation.id),
                    publishedDate: Self.date(from: translation.date)
                )
            }
        }
    }

    // upstream parse bugs arrive with the same confidence as good data: one
    // sampled series carries a chapter 8217 - the decimal entity for a right
    // single quote surviving as digits - among 261 real ones. left alone it
    // becomes a best_chapter slot, the read watermark marks the whole series read
    // on open, and the tracker pushes 8217. the bound scales with the series, so
    // a genuinely four-digit webtoon stays inside it
    static func ceiling(for numbers: [Double]) -> Double {
        guard !numbers.isEmpty else { return .greatestFiniteMagnitude }
        let sorted = numbers.sorted()
        let median = sorted[sorted.count / 2]
        return Swift.max(1000, median * 20)
    }

    // the site spells japanese `jp` and korean `kr` in its own filters, so raw
    // value matching would discard both silently
    static func language(_ code: String?) -> LanguageCode? {
        switch (code ?? "").lowercased() {
        case "en": .english
        case "zh": .chinese
        case "ja", "jp": .japanese
        case "ko", "kr": .korean
        default: nil
        }
    }

    // group._id is the upstream site slug (mangadex, comick, zinmanga) while
    // group.name is a pokemon codename standing in front of it. this string keys
    // the scanlator priority rows so it has to be stable across fetches, and a
    // decorative alias is the field most likely to be re-rolled. the handful of
    // real registered groups carry an objectid instead, and use their name
    private static func scanlator(_ group: Translation.Group?) -> String {
        if let id = group?.id, !id.isEmpty, id.firstMatch(of: /^[0-9a-f]{24}$/) == nil {
            return id.lowercased()
        }
        if let name = group?.name, !name.isEmpty { return name }
        return "MangaBall"
    }

    private static let published: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func date(from value: String?) -> Date {
        guard let value else { return .distantPast }
        return published.date(from: value) ?? .distantPast
    }
}

// MARK: - Content

extension MangaBallSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        let (data, _) = try await requester.send(get(chapterURL(chapterSlug)), for: self)
        let html = String(decoding: data, as: UTF8.self)

        // the images are in one inline assignment and nowhere else - no img tags,
        // no lazy-load attributes - so an absent array is a failure to surface
        guard let match = html.firstMatch(of: /chapterImages\s*=\s*JSON\.parse\(`([^`]*)`\)/) else {
            throw URLError(.cannotParseResponse)
        }

        let urls = try JSONDecoder().decode([String].self, from: Data(String(match.1).utf8))

        // nothing about these is validated: the cdn host varies per chapter across
        // at least two apex domains, extensions mix inside one chapter, and the
        // filenames vary by upstream. no dimensions anywhere, so layout waits for
        // the bytes
        return urls.enumerated().compactMap { index, value in
            URL(string: value).map { PageURL(index: index, url: $0) }
        }
    }
}

// MARK: - Vocabulary

extension MangaBallSource {
    struct Tag {
        let id: String
        let name: String
        let sensitivity: SourceFilter.Sensitivity

        init(_ id: String, _ name: String, _ sensitivity: SourceFilter.Sensitivity = .none) {
            self.id = id
            self.name = name
            self.sensitivity = sensitivity
        }
    }

    // declared here rather than fetched: 96 tags across five groups, small enough
    // to ship and only moving when we do, which is what lets it take part in the
    // descriptor's fingerprint honestly. the site adds a handful a year and never
    // removes, so a stale list costs a missing option and never a broken id.
    // `POST /api/v1/tag/search/` with search_type=getTagFilter is what tells you
    // this has drifted. sensitivity is ours - the site marks nothing as adult.
    //
    // the content/format/genre/origin/theme grouping is a ui convention: all five
    // serialise into the same two tri-state arrays
    static let tags: [Tag] = [
        // content
        .init("685148d115e8b86aae68e4f3", "Gore", .suggestive),
        .init("685146c5f3ed681c80f257e7", "Sexual Violence", .suggestive),
        // format
        .init("685148d115e8b86aae68e4ec", "4-Koma"),
        .init("685148cf15e8b86aae68e4de", "Adaptation"),
        .init("685148e915e8b86aae68e558", "Anthology"),
        .init("685148fe15e8b86aae68e5a7", "Award Winning"),
        .init("6851490e15e8b86aae68e5da", "Doujinshi"),
        .init("6851498215e8b86aae68e704", "Fan Colored"),
        .init("685148d615e8b86aae68e502", "Full Color"),
        .init("685148d915e8b86aae68e517", "Long Strip"),
        .init("6851493515e8b86aae68e64a", "Official Colored"),
        .init("685148eb15e8b86aae68e56c", "Oneshot"),
        .init("6851492e15e8b86aae68e633", "Self-Published"),
        .init("685148d715e8b86aae68e50d", "Web Comic"),
        // genre
        .init("685146c5f3ed681c80f257e3", "Action"),
        .init("689371f0a943baf927094f03", "Adult", .adult),
        .init("685146c5f3ed681c80f257e6", "Adventure"),
        .init("685148ef15e8b86aae68e573", "Boys' Love", .suggestive),
        .init("685146c5f3ed681c80f257e5", "Comedy"),
        .init("685148da15e8b86aae68e51f", "Crime"),
        .init("685148cf15e8b86aae68e4dd", "Drama"),
        .init("6892a73ba943baf927094e37", "Ecchi", .suggestive),
        .init("685146c5f3ed681c80f257ea", "Fantasy"),
        .init("685148da15e8b86aae68e524", "Girls' Love", .suggestive),
        .init("685148db15e8b86aae68e527", "Historical"),
        .init("685148da15e8b86aae68e520", "Horror"),
        .init("685146c5f3ed681c80f257e9", "Isekai"),
        .init("694cc2d9f8014f5e0a63ac73", "Josei(W)"),
        .init("6851490d15e8b86aae68e5d4", "Magical Girls"),
        .init("68932d11a943baf927094e7b", "Mature", .suggestive),
        .init("6851490c15e8b86aae68e5d2", "Mecha"),
        .init("6851494e15e8b86aae68e66e", "Medical"),
        .init("685148d215e8b86aae68e4f4", "Mystery"),
        .init("685148e215e8b86aae68e544", "Philosophical"),
        .init("685148d715e8b86aae68e507", "Psychological"),
        .init("694cc2d9f8014f5e0a63ac75", "Revenge"),
        .init("685148cf15e8b86aae68e4db", "Romance"),
        .init("685148cf15e8b86aae68e4da", "Sci-Fi"),
        .init("694cc2d9f8014f5e0a63ac74", "Shoujo(G)"),
        .init("689f0ab1f2e66744c6091524", "Shounen Ai", .suggestive),
        .init("685148d015e8b86aae68e4e3", "Slice of Life"),
        .init("689371f2a943baf927094f04", "Smut", .adult),
        .init("685148f515e8b86aae68e588", "Sports"),
        .init("6851492915e8b86aae68e61c", "Superhero"),
        .init("685148d915e8b86aae68e51e", "Thriller"),
        .init("685148db15e8b86aae68e529", "Tragedy"),
        .init("68932c3ea943baf927094e77", "User Created"),
        .init("6851490715e8b86aae68e5c3", "Wuxia"),
        .init("68932f68a943baf927094eaa", "Yaoi", .suggestive),
        .init("6896a885a943baf927094f66", "Yuri", .suggestive),
        // origin
        .init("68ecab8507ec62d87e62780f", "Comic"),
        .init("68ecab1e07ec62d87e627806", "Manga"),
        .init("68ecab4807ec62d87e62780b", "Manhua"),
        .init("68ecab3b07ec62d87e627809", "Manhwa"),
        // theme
        .init("6a0026ba63a8d384c0a4be13", "3D"),
        .init("6851490d15e8b86aae68e5d5", "Aliens"),
        .init("685148e715e8b86aae68e54b", "Animals"),
        .init("68bf09ff8fdeab0b6a9bc2b7", "Comics"),
        .init("685148d215e8b86aae68e4f8", "Cooking"),
        .init("685148df15e8b86aae68e534", "Crossdressing"),
        .init("685148d915e8b86aae68e519", "Delinquents"),
        .init("685146c5f3ed681c80f257e4", "Demons"),
        .init("685148d715e8b86aae68e505", "Genderswap"),
        .init("685148d615e8b86aae68e501", "Ghosts"),
        .init("685148d015e8b86aae68e4e8", "Gyaru", .suggestive),
        .init("685146c5f3ed681c80f257e8", "Harem", .suggestive),
        .init("68bfceaf4dbc442a26519889", "Hentai", .adult),
        .init("685148f215e8b86aae68e584", "Incest", .adult),
        .init("685148d715e8b86aae68e506", "Loli", .adult),
        .init("685148d915e8b86aae68e518", "Mafia"),
        .init("685148d715e8b86aae68e509", "Magic"),
        .init("68f5f5ce5f29d3c1863dec3a", "Manhwa 18+", .adult),
        .init("6851490615e8b86aae68e5c2", "Martial Arts"),
        .init("685148e215e8b86aae68e541", "Military"),
        .init("685148db15e8b86aae68e52c", "Monster Girls"),
        .init("685146c5f3ed681c80f257e2", "Monsters"),
        .init("685148d015e8b86aae68e4e4", "Music"),
        .init("685148d715e8b86aae68e508", "Ninja"),
        .init("685148d315e8b86aae68e4fd", "Office Workers"),
        .init("6851498815e8b86aae68e714", "Police"),
        .init("685148e215e8b86aae68e540", "Post-Apocalyptic"),
        .init("685146c5f3ed681c80f257e1", "Reincarnation"),
        .init("685148df15e8b86aae68e533", "Reverse Harem", .suggestive),
        .init("6851490415e8b86aae68e5b9", "Samurai"),
        .init("685148d015e8b86aae68e4e7", "School Life"),
        .init("6a0025c263a8d384c0a4be07", "Seinen"),
        .init("685148d115e8b86aae68e4ed", "Shota", .adult),
        .init("685148db15e8b86aae68e528", "Supernatural"),
        .init("685148cf15e8b86aae68e4dc", "Survival"),
        .init("6851490c15e8b86aae68e5d1", "Time Travel"),
        .init("6851493515e8b86aae68e645", "Traditional Games"),
        .init("685148f915e8b86aae68e597", "Vampires"),
        .init("685148e115e8b86aae68e53c", "Video Games"),
        .init("6851492115e8b86aae68e602", "Villainess"),
        .init("68514a1115e8b86aae68e83e", "Virtual Reality"),
        .init("6851490c15e8b86aae68e5d3", "Zombies")
    ]
}

extension MangaBallSource.Tag {
    static let options: [SourceFilter.Option] = MangaBallSource.tags.map {
        .init(id: $0.id, name: $0.name, sensitivity: $0.sensitivity)
    }

    // keyed by name because details() reads tags off the page as text, where the
    // search payload would have given ids
    static let sensitivities: [String: SourceFilter.Sensitivity] = Dictionary(
        MangaBallSource.tags.map { ($0.name.lowercased(), $0.sensitivity) },
        uniquingKeysWith: { first, _ in first }
    )
}

// MARK: - DTOs

extension MangaBallSource {
    private struct SearchResponse: Decodable {
        let data: [Item]
        let pagination: Pagination

        struct Item: Decodable {
            let id: String
            let name: String
            let cover: String?
            let adult: Bool?

            enum CodingKeys: String, CodingKey {
                case id = "_id"
                case name
                case cover
                case adult = "isAdult"
            }
        }

        struct Pagination: Decodable {
            let currentPage: Int
            let lastPage: Int

            enum CodingKeys: String, CodingKey {
                case currentPage = "current_page"
                case lastPage = "last_page"
            }
        }
    }

    private struct ChapterListing: Decodable {
        let chapters: [Chapter]

        enum CodingKeys: String, CodingKey {
            case chapters = "ALL_CHAPTERS"
        }
    }

    private struct Chapter: Decodable {
        let number: Double?
        let translations: [Translation]

        enum CodingKeys: String, CodingKey {
            case number = "number_float"
            case translations
        }
    }

    // every field but the id is optional, and volume - the one field that ever
    // crashed a reader here, typed Int and arriving as a float - is not read at
    // all. a row this source cannot use drops itself rather than failing the list
    struct Translation: Decodable {
        let id: String
        let name: String?
        let language: String?
        let group: Group?
        let date: String?

        struct Group: Decodable {
            let id: String?
            let name: String?

            enum CodingKeys: String, CodingKey {
                case id = "_id"
                case name
            }
        }
    }
}

//
//  NHentaiSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

// an adult-only source. one v2 JSON API serves search, detail and pages; the
// everythingmoe archive is a fallback only for taken-down galleries the API 404s.
// cloudflare fronts it with a silent managed challenge that mints cf_clearance on
// any real browser load, so it conforms to AuthenticatingSource MangaFire-style,
// with interactive:true to survive the under-attack toggle. see
// docs/sources/nhentai.md
struct NHentaiSource: AuthenticatingSource {
    let requester: AuthRequester
    // only for the archive host, which is plain and must not carry nhentai's
    // credential; every nhentai.net call goes through the requester via fetch(_:)
    let network: NetworkConfiguration

    private static let api = URL(string: "https://nhentai.net/api/v2")!
    private static let images = URL(string: "https://i.nhentai.net")!
    private static let thumbs = URL(string: "https://t.nhentai.net")!
    private static let archive = URL(string: "https://nhcodes.everythingmoe.com")!

    let descriptor = SourceDescriptor(
        slug: "nhentai",
        name: "nhentai",
        description: "A large doujinshi and hentai archive. Adult only.",
        icon: .nhentai,
        languages: [.english, .japanese, .chinese],
        baseURL: URL(string: "https://nhentai.net")!,
        referer: URL(string: "https://nhentai.net")!,
        supportedFilters: Self.filters,
        // the /api/v2/search sort enum, which composes with the query - so it maps
        // straight to a sort axis, no preset gymnastics
        supportedSort: .init(
            options: [
                .init(id: "popular", name: "Popular"),
                .init(id: "date", name: "Recent"),
                .init(id: "popular-today", name: "Popular today"),
                .init(id: "popular-week", name: "Popular this week"),
                .init(id: "popular-month", name: "Popular this month")
            ],
            defaultSort: "popular"
        ),
        adultOnly: true
    )

    var presets: [SourcePreset] {
        [
            .init(id: "new", name: "Recently Added", subtitle: "Freshly uploaded",
                  order: 0, sort: .init(optionID: "date")),
            .init(id: "popular-today", name: "Popular Today", subtitle: "Most viewed in the last day",
                  order: 1, sort: .init(optionID: "popular-today")),
            .init(id: "popular-week", name: "Popular This Week", subtitle: "Most viewed in the last week",
                  order: 2, sort: .init(optionID: "popular-week")),
            .init(id: "popular-month", name: "Popular This Month", subtitle: "Most viewed in the last month",
                  order: 3, sort: .init(optionID: "popular-month")),
            .init(id: "popular", name: "Popular All Time", subtitle: "Most viewed ever",
                  order: 4, sort: .init(optionID: "popular"))
        ]
    }

    // the site root 403s a plain request (Cloudflare gates the HTML), but the API
    // answers unauthenticated - so health-check the API, not the root
    var pingURL: URL { Self.api }

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

// MARK: - Vocabulary

extension NHentaiSource {
    // five namespaces harvested from /api/v2/tags/{type} into one bundled dump,
    // keyed by grammar scope and count-ordered within each. the filter id is the
    // scope search() encodes with; the option id is the name itself, because the
    // name is the request token - nhentai's grammar addresses tags by name. the
    // file's numeric ids and counts wait for /galleries/tagged and Option
    // gaining a frequency field; the full un-minified dump lives outside the
    // repo (~Downloads/nhentai-tags-full.json)
    static let filters: [SourceFilter] = {
        let vocabulary = load("nhentai-tags")
        let namespaces: [(scope: String, name: String)] = [
            ("tag", "Tags"),
            ("artist", "Artists"),
            ("character", "Characters"),
            ("parody", "Parodies"),
            ("group", "Groups")
        ]
        return namespaces.map { scope, name in
            var seen = Set<String>()
            let options: [SourceFilter.Option] = (vocabulary[scope] ?? []).compactMap { entry in
                guard seen.insert(entry.name).inserted else { return nil }
                return .init(id: entry.name, name: titled(entry.name))
            }
            return .multiSelect(id: scope, name: name, options: options, canExclude: true)
        }
    }()

    // an unreadable vocabulary is an empty filter, never a crash: the rest of
    // the source is unaffected and search still works without it
    private static func load(_ resource: String) -> [String: [Entry]] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: [Entry]].self, from: data)
        else {
            AppLog.shared.log("vocabulary \(resource).json missing or unreadable", category: "source")
            return [:]
        }
        return entries
    }

    private struct Entry: Decodable {
        let name: String

        enum CodingKeys: String, CodingKey {
            case name = "n"
        }
    }

    // nhentai stores every name lowercased, so its tags read as noise next to
    // every other source's title case - and the tag pool keys on a
    // case-insensitive normalised name, so whichever source writes a tag first
    // owns its display string. capitalisation happens at this boundary, per word
    // and per hyphen segment.
    //
    // acronyms are recognised by shape, not by a hand-kept list: a short token
    // carrying no vowel is not a word. measured against the whole bundled
    // vocabulary, every match above a handful of uses is genuine (FFM, BBM, MMF,
    // BBW, BDSM, CBT, MMM, TTF, FFF, FFT, MTF, TTM, SSBBW, TTT, MMT, CG, SSBBM)
    // and the misfires are all one-off junk tags in the single digits. a list
    // would have to be re-derived every time nhentai coins a tag; the rule
    // covers the ones nobody has coined yet
    private static let vowels = Set("aeiouy")

    // the exceptions the shape rule cannot see: acronyms carrying a vowel, and
    // ones mixing in a digit
    private static let acronyms: Set<String> = ["milf", "dilf", "3d", "3p"]

    // and the inverse - vowel-less English the rule would shout at. these are the
    // only two across all 80k names in the vocabulary
    private static let words: Set<String> = ["mr", "vs"]

    static func titled(_ name: String) -> String {
        name
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                word
                    .split(separator: "-", omittingEmptySubsequences: false)
                    .map(cased)
                    .joined(separator: "-")
            }
            .joined(separator: " ")
    }

    private static func cased(_ segment: Substring) -> String {
        let lowered = segment.lowercased()
        let shaped = (2...5).contains(segment.count)
            && segment.allSatisfy(\.isLetter)
            && !lowered.contains(where: vowels.contains)
            && !words.contains(lowered)

        if shaped || acronyms.contains(lowered) { return segment.uppercased() }
        return segment.prefix(1).uppercased() + segment.dropFirst()
    }
}

// MARK: - Search

extension NHentaiSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let raw = (query.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // the magic number: an all-digits query is a gallery code, which the
        // search index cannot match (query=671147 and id:671147 both return
        // nothing) - so it resolves through the gallery endpoint instead, live
        // first, then the takedown archive. a code that resolves nowhere falls
        // through to text search unchanged
        if query.page == 1, query.filters.isEmpty,
           (1...7).contains(raw.count), raw.allSatisfy({ $0.isASCII && $0.isNumber }),
           let match = await gallery(code: raw) {
            return SearchPage(items: [match], next: nil)
        }

        // filters ride the query string - nhentai has no filter parameters, only
        // its search grammar. the filter id is the grammar scope, the option id
        // is the name the scope takes, exclusion is a leading minus
        var terms: [String] = raw.isEmpty ? [] : [raw]
        for case let .multiSelect(scope, included, excluded) in query.filters {
            terms.append(contentsOf: included.map { "\(scope):\"\(Self.quotable($0))\"" })
            terms.append(contentsOf: excluded.map { "-\(scope):\"\(Self.quotable($0))\"" })
        }

        // /api/v2/search requires a query, but "*" is a match-all - which is what
        // unlocks the windowed popularity sorts (popular-today/week/month) for a
        // browse or a preset with no text. so one path serves search, idle browse
        // and every preset; the sort does the rest. the sibling /galleries and
        // /galleries/popular routes are unpaged or sort-blind and go unused
        let text = terms.isEmpty ? "*" : terms.joined(separator: " ")

        let response: SearchResponse = try await get(Self.url("search", [
            .init(name: "query", value: text),
            .init(name: "sort", value: resolvedSort(for: query).optionID),
            .init(name: "page", value: String(query.page))
        ]))
        return SearchPage(
            items: response.result.map(Self.stub),
            next: query.page < response.numPages ? query.page + 1 : nil
        )
    }

    // a name goes inside grammar quotes; a quote inside one would end the term
    // early and leak the rest as free text
    private static func quotable(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "")
    }

    // adultOnly, so every stub is adult by construction - gate-exempt
    private static func stub(from item: SearchItem) -> SeriesStub {
        let composite = item.englishTitle ?? item.japaneseTitle
        let names = composite.map { titles(stripped($0), language: language(from: item.tagIDs ?? [])) }

        return SeriesStub(
            slug: String(item.id),
            title: names?.first ?? "Untitled",
            cover: thumbs.appendingPathComponent(item.thumbnail),
            adult: true
        )
    }

    private func gallery(code: String) async -> SeriesStub? {
        let url = Self.url("galleries/\(code)", [.init(name: "include", value: "images,tags")])
        if let gallery: Gallery = try? await get(url) {
            let names = gallery.title.pretty.map {
                Self.titles($0, language: Self.language(from: gallery.tags))
            } ?? []
            return SeriesStub(
                slug: String(gallery.id),
                title: names.first ?? gallery.title.english ?? gallery.title.japanese ?? "Untitled",
                cover: gallery.cover.map { Self.thumbs.appendingPathComponent($0.path) },
                adult: true
            )
        }

        // a taken-down code still resolves as browse-only metadata, the same
        // fallback details() takes when opened
        guard let detail = try? await archived(code) else { return nil }
        return SeriesStub(slug: detail.slug, title: detail.title, cover: detail.covers.first, adult: true)
    }
}

// MARK: - Details

extension NHentaiSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let url = Self.url("galleries/\(seriesSlug)", [.init(name: "include", value: "images,tags")])
        let request = URLRequest(url: url)
        let (data, response) = try await requester.send(request, for: self)

        // a taken-down gallery 404s on the API but survives in the archive as
        // metadata only - no pages, so it renders but cannot be read
        if response.statusCode == 404 {
            AppLog.shared.log(
                "[nhentai] gallery \(seriesSlug) 404 on API - falling back to metadata archive (no pages, not readable)",
                category: "source"
            )
            return try await archived(seriesSlug)
        }

        let gallery = try JSONDecoder().decode(Gallery.self, from: data)
        return Self.detail(from: gallery)
    }

    private func archived(_ seriesSlug: String) async throws -> SeriesDetail {
        // shard = id % 100, zero-padded - from the archive site's own bundle
        let shard = String(format: "%02d", (Int(seriesSlug) ?? 0) % 100)
        let url = Self.archive
            .appendingPathComponent("archive")
            .appendingPathComponent(shard)
            .appendingPathComponent("\(seriesSlug).json")

        // the archive host is plain - no gate, no credential
        let data: Data = try await network.get(url: url)
        let entry = try JSONDecoder().decode(Archived.self, from: data)
        return Self.detail(from: entry)
    }
}

// MARK: - Chapters

extension NHentaiSource {
    // a gallery is one immutable book, not a chaptered series - one synthetic
    // entry standing for the whole thing
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        let url = Self.url("galleries/\(seriesSlug)", [.init(name: "include", value: "tags")])
        let gallery: Gallery = try await get(url)

        return [ChapterEntry(
            slug: seriesSlug,
            title: "",
            number: 1,
            language: Self.language(from: gallery.tags),
            // no scanlator concept on a gallery; the site itself stands in
            scanlator: "NHentai",
            url: URL(string: "https://nhentai.net/g/\(seriesSlug)/")!,
            publishedDate: Date(timeIntervalSince1970: TimeInterval(gallery.uploadDate ?? 0))
        )]
    }
}

// MARK: - Content

extension NHentaiSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        // the chapter is synthetic, so its slug is the gallery id - pages come off
        // the same detail payload
        let url = Self.url("galleries/\(seriesSlug)", [.init(name: "include", value: "images")])
        let gallery: Gallery = try await get(url)

        return (gallery.pages ?? []).map { page in
            PageURL(
                index: page.number - 1,
                // verbatim path - extensions differ per page, and nhentai emits
                // doubled ones (cover.webp.webp); never reconstruct
                url: Self.images.appendingPathComponent(page.path),
                size: page.width > 0 && page.height > 0
                    ? PageSize(width: page.width, height: page.height, exactness: .exact)
                    : nil
            )
        }
    }
}

// MARK: - Requests

extension NHentaiSource {
    private static func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    private func get<Model: Decodable>(_ url: URL) async throws -> Model {
        let data = try await fetch(url)
        return try JSONDecoder().decode(Model.self, from: data)
    }
}

// MARK: - Mapping

extension NHentaiSource {
    // a gallery is finished the moment it is posted
    private static func detail(from gallery: Gallery) -> SeriesDetail {
        // pretty is the bracket-stripped display title; the composite english
        // string is a filename, not a name, so it pools as an alternate
        let names = gallery.title.pretty.map { titles($0, language: language(from: gallery.tags)) } ?? []
        let title = names.first ?? gallery.title.english ?? gallery.title.japanese ?? "Untitled"
        let alternates = (Array(names.dropFirst()) + [gallery.title.english, gallery.title.japanese].compactMap { $0 })
            .filter { !$0.isEmpty && $0 != title }

        return SeriesDetail(
            slug: String(gallery.id),
            title: title,
            altTitles: alternates,
            synopsis: "",
            url: URL(string: "https://nhentai.net/g/\(gallery.id)/")!,
            classification: .Explicit,
            publication: .Completed,
            covers: gallery.cover.map { [thumbs.appendingPathComponent($0.path)] } ?? [],
            tags: tags(from: gallery.tags),
            authors: authors(from: gallery.tags)
        )
    }

    private static func detail(from entry: Archived) -> SeriesDetail {
        let names = entry.title.pretty.map { titles($0, language: language(from: entry.tags)) } ?? []
        let title = names.first ?? entry.title.english ?? entry.title.japanese ?? "Untitled"
        let alternates = (Array(names.dropFirst()) + [entry.title.english, entry.title.japanese].compactMap { $0 })
            .filter { !$0.isEmpty && $0 != title }

        // the archive carries no cover path - best-effort from media_id, webp being
        // nhentai's dominant format. degraded on purpose: this gallery is gone
        let covers = entry.mediaId.flatMap { media in
            thumbs.appendingPathComponent("galleries/\(media)/cover.webp")
        }.map { [$0] } ?? []

        return SeriesDetail(
            slug: String(entry.id),
            title: title,
            altTitles: alternates,
            synopsis: "",
            url: URL(string: "https://nhentai.net/g/\(entry.id)/")!,
            classification: .Explicit,
            publication: .Completed,
            covers: covers,
            tags: tags(from: entry.tags),
            authors: authors(from: entry.tags)
        )
    }

    private static let tagTypes: Set<String> = ["tag", "parody", "character", "group"]

    private static func tags(from tags: [Tag]) -> [String] {
        tags.filter { tagTypes.contains($0.type) }.map { titled($0.name) }
    }

    // artists are authors; the circle stands in when there is no named artist
    private static func authors(from tags: [Tag]) -> [String] {
        let artists = tags.filter { $0.type == "artist" }.map { titled($0.name) }
        if !artists.isEmpty { return artists }
        return tags.filter { $0.type == "group" }.map { titled($0.name) }
    }

    // the vertical bar is e-hentai's documented translated-title separator -
    // "translated works may include the translated title after a vertical bar" -
    // with the original romaji leading. measured across a 481k-gallery metadata
    // corpus, 9.8% of titles carry exactly one, and the trailing half is in the
    // language of the scan rather than english: a chinese release pipes a chinese
    // title. so the half worth leading with is the one matching the gallery's own
    // language, and the other pools as an alternate the user can switch to.
    // spacing around the bar is not dependable - 7% omit the leading space.
    //
    // the same bar in the tag namespaces means alias, not translation, and its
    // order is not a language rule ("my hero academia | boku no hero academia"
    // against "kimetsu no yaiba | demon slayer") - those are left intact
    private static func titles(_ pretty: String, language: LanguageCode) -> [String] {
        guard let bar = pretty.firstIndex(of: "|") else { return [pretty] }

        let original = pretty[..<bar].trimmingCharacters(in: .whitespaces)
        let translated = pretty[pretty.index(after: bar)...].trimmingCharacters(in: .whitespaces)
        guard !original.isEmpty, !translated.isEmpty else { return [pretty] }

        return language == .japanese ? [original, translated] : [translated, original]
    }

    // the composite title is a filename: bracket, paren and brace groups carry the
    // event, circle, language and scanlator, and the name is what survives them.
    // this is what nhentai's own pretty field means to be, and it is better at it -
    // pretty also eats ~tilde~ and -hyphen- pairs, so "Mitsurin Yuusha Dorei-ka
    // Keikaku Bitch of the Jungle - Enslaved" reaches it as "Mitsurin Yuusha
    // DoreiEnslaved". measured over 25k galleries the two agree 89.1% of the time
    // and every disagreement is pretty losing title text. a title left empty by
    // stripping (13 in 25k, all unbalanced uploader typos) keeps its composite
    private static func stripped(_ composite: String) -> String {
        var text = composite
        for pattern in [#"\[[^\[\]]*\]"#, #"\([^()]*\)"#, #"\{[^{}]*\}"#] {
            var previous: String
            repeat {
                previous = text
                text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            } while text != previous
        }

        let name = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? composite : name
    }

    private static func language(from tags: [Tag]) -> LanguageCode {
        let names = Set(tags.filter { $0.type == "language" }.map(\.name))
        if names.contains("japanese") { return .japanese }
        if names.contains("chinese") { return .chinese }
        return .english
    }

    // a search item names no tags, only their ids, so the language namespace is
    // matched by id instead - the three the app models, taken from
    // /api/v2/tags/language. precedence mirrors the name-keyed lookup above
    private enum Namespace {
        static let japanese = 6346
        static let chinese = 29963
    }

    private static func language(from ids: [Int]) -> LanguageCode {
        let ids = Set(ids)
        if ids.contains(Namespace.japanese) { return .japanese }
        if ids.contains(Namespace.chinese) { return .chinese }
        return .english
    }
}

// MARK: - DTOs

extension NHentaiSource {
    private struct SearchResponse: Decodable {
        let result: [SearchItem]
        let numPages: Int

        enum CodingKeys: String, CodingKey {
            case result
            case numPages = "num_pages"
        }
    }

    private struct SearchItem: Decodable {
        let id: Int
        let englishTitle: String?
        let japaneseTitle: String?
        let thumbnail: String
        let tagIDs: [Int]?

        enum CodingKeys: String, CodingKey {
            case id, thumbnail
            case englishTitle = "english_title"
            case japaneseTitle = "japanese_title"
            case tagIDs = "tag_ids"
        }
    }

    private struct Gallery: Decodable {
        let id: Int
        let title: Title
        let cover: Image?
        let tags: [Tag]
        let uploadDate: Int?
        let pages: [Page]?

        enum CodingKeys: String, CodingKey {
            case id, title, cover, tags, pages
            case uploadDate = "upload_date"
        }
    }

    private struct Archived: Decodable {
        let id: Int
        let mediaId: String?
        let title: Title
        let tags: [Tag]

        enum CodingKeys: String, CodingKey {
            case id, title, tags
            case mediaId = "media_id"
        }
    }

    private struct Title: Decodable {
        let english: String?
        let japanese: String?
        let pretty: String?
    }

    private struct Tag: Decodable {
        let type: String
        let name: String
    }

    private struct Image: Decodable {
        let path: String
    }

    private struct Page: Decodable {
        let number: Int
        let path: String
        let width: Int
        let height: Int
    }
}

//
//  NHentaiSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import Foundation

struct NHentaiSource: AuthenticatingSource {
    let requester: AuthRequester
    // network is for the archive host only - it is plain and must not carry
    // nhentai's credential; every nhentai.net call goes through the requester
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
        supportedSort: .init(
            options: [
                .init(id: "popular", name: "Popular"),
                .init(id: "date", name: "Recent"),
                .init(id: "popular-today", name: "Popular today"),
                .init(id: "popular-week", name: "Popular this week"),
                .init(id: "popular-month", name: "Popular this month"),
            ],
            defaultSort: "popular"
        ),
        adultOnly: true
    )

    var presets: [SourcePreset] {
        [
            .init(
                id: "new", name: "Recently Added", subtitle: "Freshly uploaded",
                order: 0, sort: .init(optionID: "date")),
            .init(
                id: "popular-today", name: "Popular Today", subtitle: "Most viewed in the last day",
                order: 1, sort: .init(optionID: "popular-today")),
            .init(
                id: "popular-week", name: "Popular This Week",
                subtitle: "Most viewed in the last week",
                order: 2, sort: .init(optionID: "popular-week")),
            .init(
                id: "popular-month", name: "Popular This Month",
                subtitle: "Most viewed in the last month",
                order: 3, sort: .init(optionID: "popular-month")),
            .init(
                id: "popular", name: "Popular All Time", subtitle: "Most viewed ever",
                order: 4, sort: .init(optionID: "popular")),
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
            interactive: true,
            pinChallengeURL: true
        )
    }
}

// MARK: - Vocabulary

extension NHentaiSource {
    // option id is the tag name itself, not a numeric id - nhentai's search
    // grammar addresses tags by name
    static let filters: [SourceFilter] = {
        let vocabulary = load("nhentai-tags")
        let namespaces: [(scope: String, name: String)] = [
            ("tag", "Tags"),
            ("artist", "Artists"),
            ("character", "Characters"),
            ("parody", "Parodies"),
            ("group", "Groups"),
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

    private static func load(_ resource: String) -> [String: [Entry]] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([String: [Entry]].self, from: data)
        else {
            AppLog.shared.log(
                "vocabulary \(resource).json missing or unreadable", level: .warning,
                category: "source")
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

    // nhentai stores every tag name lowercased, and the shared tag pool keys on
    // a case-insensitive name - whichever source writes a tag first owns its
    // display string, so capitalisation has to happen at this boundary
    //
    // acronyms are recognised by shape (a short, vowel-less token), not a
    // hand-kept list - a list would need re-deriving every time nhentai coins
    // a new tag, where the shape rule covers those automatically
    private static let vowels = Set("aeiouy")

    // exceptions the shape rule gets wrong: acronyms with a vowel or a digit
    private static let acronyms: Set<String> = ["milf", "dilf", "3d", "3p"]

    // and the inverse - vowel-less english words the rule would wrongly uppercase
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
        let shaped =
            (2...5).contains(segment.count)
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

        // an all-digits query is a gallery code, which the search index cannot
        // match - resolve it through the gallery endpoint instead. one that
        // resolves nowhere falls through to text search unchanged
        if query.page == 1, query.filters.isEmpty,
            (1...7).contains(raw.count), raw.allSatisfy({ $0.isASCII && $0.isNumber }),
            let match = await gallery(code: raw)
        {
            return SearchPage(items: [match], next: nil)
        }

        var terms: [String] = raw.isEmpty ? [] : [raw]
        for case .multiSelect(let scope, let included, let excluded) in query.filters {
            terms.append(contentsOf: included.map { "\(scope):\"\(Self.quotable($0))\"" })
            terms.append(contentsOf: excluded.map { "-\(scope):\"\(Self.quotable($0))\"" })
        }

        // /api/v2/search requires a query, but "*" is a match-all - so this one
        // path also serves idle browse and every preset, since the sibling
        // /galleries routes are unpaged or don't support these sorts
        let text = terms.isEmpty ? "*" : terms.joined(separator: " ")

        let response: SearchResponse = try await get(
            Self.url(
                "search",
                [
                    .init(name: "query", value: text),
                    .init(name: "sort", value: resolvedSort(for: query).optionID),
                    .init(name: "page", value: String(query.page)),
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

    private static func stub(from item: SearchItem) -> SeriesStub {
        let composite = item.englishTitle ?? item.japaneseTitle
        let names = composite.map {
            titles(stripped($0), language: language(from: item.tagIDs ?? []))
        }

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
            let names =
                gallery.title.pretty.map {
                    Self.titles($0, language: Self.language(from: gallery.tags))
                } ?? []
            return SeriesStub(
                slug: String(gallery.id),
                title: names.first ?? gallery.title.english ?? gallery.title.japanese ?? "Untitled",
                cover: gallery.cover.map { Self.thumbs.appendingPathComponent($0.path) },
                adult: true
            )
        }

        // same archive fallback details() takes when the gallery is opened
        guard let detail = try? await archived(code) else { return nil }
        return SeriesStub(
            slug: detail.slug, title: detail.title, cover: detail.covers.first, adult: true)
    }
}

// MARK: - Details

extension NHentaiSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let url = Self.url(
            "galleries/\(seriesSlug)", [.init(name: "include", value: "images,tags")])
        let request = URLRequest(url: url)
        let (data, response) = try await requester.send(request, for: self)

        if response.statusCode == 404 {
            AppLog.shared.log(
                "[nhentai] gallery \(seriesSlug) 404 on API - falling back to metadata archive (no pages, not readable)",
                level: .warning,
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

        let data: Data = try await network.get(url: url)
        let entry = try JSONDecoder().decode(Archived.self, from: data)
        return Self.detail(from: entry)
    }
}

// MARK: - Chapters

extension NHentaiSource {
    func chapters(seriesSlug: String) async throws -> [ChapterEntry] {
        let url = Self.url("galleries/\(seriesSlug)", [.init(name: "include", value: "tags")])
        let gallery: Gallery = try await get(url)

        return [
            ChapterEntry(
                slug: seriesSlug,
                title: "",
                number: 1,
                language: Self.language(from: gallery.tags),
                scanlator: "NHentai",
                url: URL(string: "https://nhentai.net/g/\(seriesSlug)/")!,
                publishedDate: Date(timeIntervalSince1970: TimeInterval(gallery.uploadDate ?? 0))
            )
        ]
    }
}

// MARK: - Content

extension NHentaiSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        // chapterSlug is unused - the chapter is synthetic, so it's the same
        // gallery id as seriesSlug and pages come off the same detail payload
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
        var components = URLComponents(
            url: api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
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
    private static func detail(from gallery: Gallery) -> SeriesDetail {
        let names =
            gallery.title.pretty.map { titles($0, language: language(from: gallery.tags)) } ?? []
        let title = names.first ?? gallery.title.english ?? gallery.title.japanese ?? "Untitled"
        let alternates =
            (Array(names.dropFirst())
            + [gallery.title.english, gallery.title.japanese].compactMap { $0 })
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
        let names =
            entry.title.pretty.map { titles($0, language: language(from: entry.tags)) } ?? []
        let title = names.first ?? entry.title.english ?? entry.title.japanese ?? "Untitled"
        let alternates =
            (Array(names.dropFirst())
            + [entry.title.english, entry.title.japanese].compactMap { $0 })
            .filter { !$0.isEmpty && $0 != title }

        // the archive carries no cover path - guess it from media_id, webp
        // being nhentai's dominant format, since this gallery is gone
        let covers =
            entry.mediaId.flatMap { media in
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

    private static func authors(from tags: [Tag]) -> [String] {
        let artists = tags.filter { $0.type == "artist" }.map { titled($0.name) }
        if !artists.isEmpty { return artists }
        return tags.filter { $0.type == "group" }.map { titled($0.name) }
    }

    // the vertical bar is e-hentai's documented translated-title separator,
    // original romaji leading - but the trailing half is in the scan's own
    // language rather than always english, so the half worth leading with is
    // whichever matches the gallery's language; the other pools as an alternate
    //
    // this is title-only: the same bar in tag namespaces means alias, not
    // translation, and carries no language ordering - leave those intact
    private static func titles(_ pretty: String, language: LanguageCode) -> [String] {
        guard let bar = pretty.firstIndex(of: "|") else { return [pretty] }

        let original = pretty[..<bar].trimmingCharacters(in: .whitespaces)
        let translated = pretty[pretty.index(after: bar)...].trimmingCharacters(in: .whitespaces)
        guard !original.isEmpty, !translated.isEmpty else { return [pretty] }

        return language == .japanese ? [original, translated] : [translated, original]
    }

    // the composite title is a filename: bracket, paren and brace groups carry
    // event/circle/language/scanlator, and the name is what survives stripping
    // them. this exists rather than just using nhentai's own "pretty" field
    // because pretty also eats ~tilde~ and -hyphen- pairs, sometimes losing
    // title text (e.g. "Dorei-ka Keikaku - Enslaved" becomes "DoreiEnslaved")
    private static func stripped(_ composite: String) -> String {
        var text = composite
        for pattern in [#"\[[^\[\]]*\]"#, #"\([^()]*\)"#, #"\{[^{}]*\}"#] {
            var previous: String
            repeat {
                previous = text
                text = text.replacingOccurrences(
                    of: pattern, with: " ", options: .regularExpression)
            } while text != previous
        }

        let name =
            text
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

    // search results carry tag ids, not names, so language is matched by id
    // here instead - mirrors the precedence of the name-keyed lookup above
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

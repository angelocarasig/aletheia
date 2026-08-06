//
//  ComixSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import SwiftSoup

struct ComixSource: SourceService, AuthenticatingSource {
    let requester: AuthRequester
    let renderer: WebRenderer

    private let defaultSortID = "relevance:desc"

    let descriptor = SourceDescriptor(
        slug: "comix",
        name: "Comix",
        description: "Comix is the best site for reading manga, manhwa, manhua online for free. Updated daily with the latest chapters.",
        icon: .comix,
        languages: [.english],
        baseURL: URL(string: "https://comix.to")!,
        referer: URL(string: "https://comix.to")!,
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
                id: "demos",
                name: "Demographic",
                options: [
                    .init(id: "3", name: "Josei"),
                    .init(id: "4", name: "Seinen"),
                    .init(id: "1", name: "Shoujo"),
                    .init(id: "2", name: "Shounen")
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
                    .init(id: "not_yet_released", name: "Not Yet Released")
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
                    .init(id: "6", name: "Action"),
                    .init(id: "87264", name: "Adult", nsfw: true),
                    .init(id: "7", name: "Adventure"),
                    .init(id: "8", name: "Boys Love"),
                    .init(id: "9", name: "Comedy"),
                    .init(id: "10", name: "Crime"),
                    .init(id: "11", name: "Drama"),
                    .init(id: "87265", name: "Ecchi"),
                    .init(id: "12", name: "Fantasy"),
                    .init(id: "13", name: "Girls Love"),
                    .init(id: "40", name: "Harem"),
                    .init(id: "87266", name: "Hentai", nsfw: true),
                    .init(id: "14", name: "Historical"),
                    .init(id: "15", name: "Horror"),
                    .init(id: "16", name: "Isekai"),
                    .init(id: "17", name: "Magical Girls"),
                    .init(id: "87267", name: "Mature"),
                    .init(id: "18", name: "Mecha"),
                    .init(id: "19", name: "Medical"),
                    .init(id: "20", name: "Mystery"),
                    .init(id: "21", name: "Philosophical"),
                    .init(id: "22", name: "Psychological"),
                    .init(id: "23", name: "Romance"),
                    .init(id: "24", name: "Sci-Fi"),
                    .init(id: "25", name: "Slice of Life"),
                    .init(id: "87268", name: "Smut", nsfw: true),
                    .init(id: "26", name: "Sports"),
                    .init(id: "27", name: "Superhero"),
                    .init(id: "28", name: "Thriller"),
                    .init(id: "29", name: "Tragedy"),
                    .init(id: "30", name: "Wuxia"),
                    .init(id: "93164", name: "4-Koma"),
                    .init(id: "93167", name: "Adaptation"),
                    .init(id: "93165", name: "Anthology"),
                    .init(id: "93166", name: "Award Winning"),
                    .init(id: "93169", name: "Doujinshi"),
                    .init(id: "93170", name: "Full Color"),
                    .init(id: "93172", name: "Long Strip"),
                    .init(id: "93168", name: "Oneshot"),
                    .init(id: "93171", name: "Web Comic")
                ],
                canExclude: true
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
                    .init(id: "views_7d:desc", name: "Most viewed · 7 days"),
                    .init(id: "views_30d:desc", name: "Most viewed · 30 days"),
                    .init(id: "views_90d:desc", name: "Most viewed · 90 days"),
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
            .init(id: "trending", name: "Trending", subtitle: "Most read this week", order: 0,
                  sort: .init(optionID: "views_7d:desc", ascending: false)),
            .init(id: "latest", name: "Latest Updates", subtitle: "Freshly released chapters", order: 1,
                  sort: .init(optionID: "updated_at:desc", ascending: false)),
            .init(id: "new", name: "New Releases", subtitle: "Recently added series", order: 2,
                  sort: .init(optionID: "created_at:desc", ascending: false)),
            .init(id: "top-rated", name: "Top Rated", subtitle: "Highest scored on Comix", order: 3,
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

extension ComixSource {
    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub> {
        let url = browseURL(for: query)
        let credential = try await requester.credential(for: self)
        let json = try await renderer.sniff(url, credential: credential, matching: "/api/v1/manga?")
        let response = try JSONDecoder().decode(MangaResponse.self, from: Data(json.utf8))

        let items = response.result.items.map { item in
            SeriesStub(
                slug: item.hid,
                title: item.title,
                cover: (item.poster?.large ?? item.poster?.medium).flatMap { URL(string: $0) },
                latestChapterNumber: item.latestChapter,
                latestChapterDate: RelativeDate.parse(item.chapterUpdatedAtFormatted)
            )
        }
        let meta = response.result.meta
        return SearchPage(items: items, next: meta.hasNext ? meta.page + 1 : nil)
    }

    private struct MangaResponse: Decodable {
        let result: Result

        struct Result: Decodable {
            let items: [Item]
            let meta: Meta
        }
        struct Item: Decodable {
            let hid: String
            let title: String
            // null on some entries, and a non-optional here failed the whole page
            // rather than the one item that had no artwork
            let poster: Poster?
            let latestChapter: Double?
            let chapterUpdatedAtFormatted: String?
        }
        struct Poster: Decodable {
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
            items.append(URLQueryItem(name: "q", value: text))
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

extension ComixSource {
    func details(seriesSlug: String) async throws -> SeriesDetail {
        let url = descriptor.baseURL
            .appendingPathComponent("title")
            .appendingPathComponent(seriesSlug)

        let data = try await NetworkService().get(url: url, headers: ["Referer": descriptor.referer.absoluteString])
        let html = String(decoding: data, as: UTF8.self)
        let detail = try Self.detail(from: html, hid: seriesSlug)

        var tags: [String] = []
        tags += (detail.genres ?? []).map(\.title)
        tags += (detail.formats ?? []).map(\.title)
        tags += (detail.demographics ?? []).map(\.title)
        tags += (detail.tags ?? []).map(\.title)

        var authors: [String] = []
        authors += (detail.authors ?? []).map(\.title)
        authors += (detail.artists ?? []).map(\.title)
        let cover = (detail.poster?.large ?? detail.poster?.medium).flatMap { URL(string: $0) }

        return SeriesDetail(
            slug: detail.hid,
            title: detail.title,
            altTitles: detail.altTitles ?? [],
            synopsis: HTMLMarkdown.from(detail.synopsisHtml ?? ""),
            url: URL(string: detail.url, relativeTo: descriptor.baseURL)?.absoluteURL ?? url,
            classification: Classification(rating: detail.contentRating),
            publication: Publication(status: detail.status),
            covers: cover.map { [$0] } ?? [],
            tags: tags,
            authors: authors
        )
    }

    // details are server-rendered into a React Query cache embedded as
    // <script id="initial-data">; the title lives at queries["[manga,detail,<hid>]"].
    private static func detail(from html: String, hid: String) throws -> ComixDetail {
        let document = try SwiftSoup.parse(html)
        guard let script = try document.select("script#initial-data").first() else {
            throw URLError(.cannotParseResponse)
        }
        let root = try JSONSerialization.jsonObject(with: Data(script.data().utf8)) as? [String: Any]
        let key = "[\"manga\",\"detail\",\"\(hid)\"]"
        guard let queries = root?["queries"] as? [String: Any],
              let object = queries[key] else {
            throw URLError(.cannotParseResponse)
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ComixDetail.self, from: data)
    }

    private struct ComixDetail: Decodable {
        let hid: String
        let title: String
        let url: String
        let status: String?
        let contentRating: String?
        let synopsisHtml: String?
        let altTitles: [String]?
        let poster: Poster?
        let genres: [Tag]?
        let formats: [Tag]?
        let demographics: [Tag]?
        let tags: [Tag]?
        let authors: [Tag]?
        let artists: [Tag]?

        struct Poster: Decodable {
            let medium: String?
            let large: String?
        }
        struct Tag: Decodable {
            let title: String
        }
    }
}

// MARK: - Chapters

extension ComixSource {
    // the chapter response is encrypted on the wire, so the only plaintext is
    // what the site's own bundle produces. tapping that beats scraping the
    // rendered rows; the scrape stays as the fallback for when comix moves.
    func chapters(seriesSlug: String, have: Int) async throws -> [ChapterEntry]? {
        do {
            let entries = try await tapped(seriesSlug: seriesSlug, have: have)
            guard let entries else { return nil }
            if !entries.isEmpty { return entries }
            AppLog.shared.log("chapter tap came back empty, scraping instead", category: "comix")
        } catch {
            AppLog.shared.log("chapter tap failed (\(error)), scraping instead", category: "comix")
        }
        return try await scraped(seriesSlug: seriesSlug)
    }

    // nil when the server's total still matches what the caller holds
    private func tapped(seriesSlug: String, have: Int) async throws -> [ChapterEntry]? {
        let pageURL = descriptor.baseURL
            .appendingPathComponent("title")
            .appendingPathComponent(seriesSlug)
        let credential = try await requester.credential(for: self)

        let json = try await renderer.run(
            pageURL,
            credential: credential,
            installing: Self.chapterTap,
            // the fast path polls for the module itself, so nothing here waits on
            // rendered rows - the walk does its own waiting if it gets that far
            script: Self.chapterScript,
            arguments: [
                "hid": seriesSlug,
                "have": have,
                "wide": Self.wideLimit,
                "narrow": Self.safeLimit,
                "lanes": Self.lanes,
                "poll": Self.pollInterval,
                "deadline": Self.pageDeadline,
                "budget": Self.walkBudget,
                "cap": Self.pageCap
            ],
            // the watchdog has to outlast the script's own budget, or it tears the
            // page down mid-walk and the script never gets to hand back what it
            // collected. a long series is ~97 clicks at the site's own pace
            timeout: .milliseconds(Self.walkBudget + Self.walkGrace)
        )
        let harvest = try JSONDecoder().decode(ComixHarvest.self, from: Data(json.utf8))

        if harvest.unchanged {
            AppLog.shared.log("server total still \(have), keeping stored chapters", category: "comix")
            return nil
        }

        var seen = Set<String>()
        let entries = harvest.chapters.compactMap { chapter -> ChapterEntry? in
            guard let entry = chapterEntry(from: chapter, seriesURL: pageURL),
                  seen.insert(entry.slug).inserted else { return nil }
            return entry
        }

        let paced = harvest.timings.sorted()
        let pacing = paced.isEmpty ? "n/a" : "\(paced[0])/\(paced[paced.count / 2])/\(paced[paced.count - 1])ms"

        AppLog.shared.log(
            "tapped \(harvest.chapters.count) row(s) over \(harvest.pages) of \(harvest.expected.map(String.init) ?? "?") page(s), server total \(harvest.total.map(String.init) ?? "?"), per-page min/med/max \(pacing) -> \(entries.count) chapter(s)",
            category: "comix"
        )

        // a short list is worse than a slow one - the scrape is the safer answer
        if let total = harvest.total, harvest.chapters.count < total {
            throw RenderError.noContent
        }
        return entries
    }

    private func scraped(seriesSlug: String) async throws -> [ChapterEntry] {
        let pageURL = descriptor.baseURL
            .appendingPathComponent("title")
            .appendingPathComponent(seriesSlug)
        let credential = try await requester.credential(for: self)
        let pages = try await renderer.renderPaged(
            pageURL,
            credential: credential,
            waitingFor: "section.mpage__chapters ul.mchap-list li.mchap-item",
            advancing: ".mchap-foot nav.npager button[aria-label='Next page']",
            trackingFirst: "section.mpage__chapters ul.mchap-list li.mchap-item a.mchap-row__primary",
            // the 30-page default silently returned ~600 of 1925 rows on a long
            // series - a short list is the bug this whole path exists to avoid
            maxPages: Self.pageCap
        )

        var seen = Set<String>()
        var entries: [ChapterEntry] = []
        for html in pages {
            let document = try SwiftSoup.parse(html, descriptor.baseURL.absoluteString)
            let rows = try document.select("section.mpage__chapters ul.mchap-list li.mchap-item")
            for row in rows.array() {
                guard let entry = try chapterEntry(from: row, seriesURL: pageURL), seen.insert(entry.slug).inserted else { continue }
                entries.append(entry)
            }
        }
        return entries
    }

    private func chapterEntry(from row: Element, seriesURL: URL) throws -> ChapterEntry? {
        guard let link = try row.select("a.mchap-row__primary").first() else { return nil }
        let href = try link.attr("href")
        guard !href.isEmpty else { return nil }

        // href: /title/<seriesSlug>/<id>-chapter-<n>  → keep the full chapter segment
        // (the reader path needs it verbatim: /title/<fullSlug>/<id>-chapter-<n>)
        let slug = href.split(separator: "/").last.map(String.init) ?? href

        let chapterText = try link.select("span.mchap-row__ch").first()?.text() ?? ""
        let subtitle = try link.select("span.mchap-row__title").first()?.text()
        let group = try row.select("a.mchap-row__group").first()?.text()
        let uploader = try row.select("a.mchap-row__uploader").first()?.text()
        let time = try row.select("span.mchap-row__time").first()?.text()

        let digits = chapterText.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }

        return ChapterEntry(
            slug: slug,
            title: (subtitle?.isEmpty == false ? subtitle : nil) ?? chapterText,
            number: Double(digits) ?? 0,
            language: .english,
            scanlator: nonEmpty(group) ?? nonEmpty(uploader) ?? "Comix",
            url: URL(string: href, relativeTo: descriptor.baseURL)?.absoluteURL ?? seriesURL,
            publishedDate: RelativeDate.parse(time) ?? .distantPast
        )
    }

    private func nonEmpty(_ text: String?) -> String? {
        (text?.isEmpty == false) ? text : nil
    }

    private func chapterEntry(from chapter: ComixChapter, seriesURL: URL) -> ChapterEntry? {
        guard !chapter.url.isEmpty else { return nil }

        // the reader path needs this verbatim: /title/<fullSlug>/<id>-chapter-<n>
        let slug = chapter.url.split(separator: "/").last.map(String.init) ?? chapter.url
        let number = chapter.number ?? 0

        return ChapterEntry(
            slug: slug,
            title: nonEmpty(chapter.name) ?? "Chapter \(chapterNumber(number))",
            number: number,
            language: .english,
            scanlator: nonEmpty(chapter.group?.name) ?? "Comix",
            url: URL(string: chapter.url, relativeTo: descriptor.baseURL)?.absoluteURL ?? seriesURL,
            publishedDate: RelativeDate.parse(chapter.createdAtFormatted) ?? .distantPast
        )
    }

    private struct ComixHarvest: Decodable {
        let unchanged: Bool
        let pages: Int
        let expected: Int?
        let total: Int?
        let timings: [Int]
        let chapters: [ComixChapter]
    }

    private struct ComixChapter: Decodable {
        let id: Int
        let url: String
        let number: Double?
        let name: String?
        let createdAtFormatted: String?
        let group: Group?

        struct Group: Decodable {
            let name: String?
        }
    }

    private func chapterNumber(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }

    // 20 is the component's default, not a server ceiling. 100 is the highest
    // anyone has confirmed, so ask for more and fall back to it - the rows the
    // server actually returns tell us what it honoured
    private static let wideLimit = 500
    private static let safeLimit = 100
    private static let lanes = 12
    private static let pollInterval = 150
    private static let pageDeadline = 8000
    private static let walkBudget = 120_000
    private static let walkGrace = 30_000
    private static let pageCap = 500

    // installed at documentStart, before the site's bundle runs - the only
    // moment a native can still be wrapped without the page noticing. every
    // decrypted payload passes through JSON.parse on its way into react.
    private static let chapterTap = """
    (function () {
      if (window.__chapterTapInstalled) return;
      window.__chapterTapInstalled = true;

      var queue = [];
      var raw = JSON.parse;

      var harvest = function (value) {
        try {
          if (!value || typeof value !== 'object') return;
          var result = (value.result && typeof value.result === 'object') ? value.result : value;
          var items = result.items;
          if (!Array.isArray(items) || !items.length) return;
          var first = items[0];
          if (!first || typeof first !== 'object') return;
          if (!('id' in first) || !('number' in first)) return;
          // the server states page/lastPage/hasNext/total outright - keeping it
          // beats inferring "are we done" from row counts and timeouts
          if (result.meta && typeof result.meta === 'object') window.__chapterMeta = result.meta;
          for (var i = 0; i < items.length; i++) queue.push(items[i]);
        } catch (e) {}
      };

      JSON.parse = new Proxy(raw, {
        apply: function (target, thisArg, args) {
          var out = Reflect.apply(target, thisArg, args);
          harvest(out);
          return out;
        }
      });

      window.__chapterTake = function () {
        var batch = queue;
        queue = [];
        return batch;
      };

    })();
    """

    // one round trip: walks the pager to the end in-page and hands back every
    // chapter it tapped. stops on the site's own disabled next button rather
    // than a page guess, so long series stop truncating.
    private static let chapterScript = """
    const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const list = () => document.querySelector('ul.mchap-list');

    const appear = async () => {
      for (let i = 0; i < 20; i++) {
        const node = list();
        if (node && node.children.length) return true;
        await pause(250);
      }
      return false;
    };

    const next = (page) => {
      const buttons = Array.from(document.querySelectorAll('.mchap-foot button')).filter((b) => !b.disabled);
      const labelled = buttons.find((b) => /\\bnext\\b/i.test([
        b.getAttribute('aria-label'), b.getAttribute('title'), b.textContent
      ].join(' ')));
      if (labelled) return labelled;
      return buttons.find((b) => (b.textContent || '').trim() === String(page + 1)) || null;
    };

    const seen = new Set();
    const chapters = [];
    const collect = (items) => {
      for (const item of items) {
        if (!item || item.id === null || item.id === undefined) continue;
        const key = String(item.id);
        if (seen.has(key)) continue;
        seen.add(key);
        chapters.push(item);
      }
    };
    const drain = () => collect(window.__chapterTake ? window.__chapterTake() : []);

    const unwrap = (payload) => {
      const body = (payload && payload.result && typeof payload.result === 'object') ? payload.result : payload;
      return body || {};
    };
    const rowsOf = (payload) => {
      const items = unwrap(payload).items;
      return Array.isArray(items) ? items : [];
    };
    const metaOf = (payload) => {
      const body = unwrap(payload);
      return (body.meta && typeof body.meta === 'object') ? body.meta : body;
    };
    const firstNumber = (source, keys) => {
      for (const key of keys) {
        const value = source[key];
        if (typeof value === 'number' && value > 0) return value;
      }
      return null;
    };

    // comix's own es module owns both the request signer and the response
    // decryptor. es modules are cached singletons, so importing it by url hands
    // back the live instance the app is already using - asking it for limit=100
    // gets a request signed FOR limit=100, rather than us editing a url it has
    // already signed, which is what the server rejects. export names rotate per
    // deploy, so the handle is found by shape and never by name.
    // polls for the module rather than for rendered rows - the fast path never
    // touches the dom, so waiting on the chapter list is a second wasted
    const client = async () => {
      for (let waited = 0; waited < deadline; waited += poll) {
        const url = performance.getEntriesByType('resource')
          .map((entry) => entry.name)
          .find((name) => name.indexOf('/env-') !== -1 && name.indexOf('.js') !== -1);

        if (url) {
          const loaded = await import(url);
          const handles = [loaded.c, loaded.default].concat(Object.values(loaded));
          for (const handle of handles) {
            if (handle && typeof handle.chapters === 'function') return handle;
          }
          return null;
        }
        await pause(poll);
      }
      return null;
    };

    // the site's axios bakes in a 15s timeout that cannot be overridden
    const request = async (api, page, limit) => {
      for (let attempt = 0; ; attempt++) {
        try {
          return await api.chapters(hid, { page: page, limit: limit, order: { number: 'desc' } });
        } catch (error) {
          const reason = String((error && error.code) || (error && error.message) || error);
          if (attempt >= 2 || !/timeout|ECONNABORTED/i.test(reason)) throw error;
          await pause(poll * (attempt + 1));
        }
      }
    };

    const viaModule = async () => {
      const api = await client();
      if (!api) return null;

      const timings = [];
      const call = async (page, limit) => {
        const started = Date.now();
        const payload = await request(api, page, limit);
        timings.push(Date.now() - started);
        return payload;
      };

      // ask past the known ceiling; if the server refuses outright rather than
      // clamping, drop to the limit that is known to work
      let first;
      try {
        first = await call(1, wide);
      } catch (error) {
        first = await call(1, narrow);
      }

      const rows = rowsOf(first);
      if (!rows.length) return null;

      const meta = metaOf(first);
      const total = firstNumber(meta, ['total', 'totalCount', 'total_count', 'count']);

      // the count the server reports is the whole answer when it matches what
      // the caller already has - the other pages are not worth fetching
      if (have > 0 && total === have) {
        return { unchanged: true, pages: 1, expected: null, total: total, timings: timings, chapters: [] };
      }

      collect(rows);

      // however many rows came back IS the honoured page size, whatever we asked
      const granted = rows.length;
      let last = firstNumber(meta, ['lastPage', 'last_page', 'pages', 'totalPages', 'total_pages']);
      if (total) last = Math.ceil(total / granted);
      last = Math.min(last || 1, cap);

      const queue = [];
      for (let page = 2; page <= last; page++) queue.push(page);

      while (queue.length) {
        const batch = queue.splice(0, lanes);
        const landed = await Promise.all(batch.map((page) => call(page, granted).then(rowsOf)));
        for (const items of landed) collect(items);
      }

      return {
        unchanged: false,
        pages: last,
        expected: last,
        total: total,
        timings: timings,
        chapters: chapters
      };
    };

    // the rows are rendered FROM the decrypted payload, so the first row's href
    // changing proves that payload already passed through the tap. it is the
    // signal the html scrape uses, and it settles in well under a second -
    // polling for tapped rows instead burned the full deadline on every page.
    const head = () => {
      const row = document.querySelector('ul.mchap-list a.mchap-row__primary');
      return row ? row.getAttribute('href') : null;
    };

    const arrive = async (before) => {
      for (let waited = 0; waited < deadline; waited += poll) {
        await pause(poll);
        if (head() !== before) { drain(); return true; }
      }
      drain();
      return false;
    };

    const meta = () => window.__chapterMeta || {};
    const pick = (...keys) => {
      const m = meta();
      for (const key of keys) if (typeof m[key] === 'number' && m[key] > 0) return m[key];
      return null;
    };
    const lastPage = () => pick('lastPage', 'last_page', 'pageCount');
    const more = () => {
      const m = meta();
      const flag = m.hasNext !== undefined ? m.hasNext : m.has_next;
      if (typeof flag === 'boolean') return flag;
      const last = lastPage();
      return last === null ? true : page < last;
    };

    // one page per click, twenty rows a page. kept because the module handle is
    // found by shape and this site rewrites its bundle most weeks
    const viaWalk = async () => {
      drain();

      let page = 1;
      let dry = 0;
      const timings = [];
      // a wall clock on the walk itself, so a pager that never reports an end
      // returns what it has instead of running to the cap
      const stopAt = Date.now() + budget;
      while (page < cap && more() && Date.now() < stopAt) {
        const button = next(page);
        if (!button) break;
        const started = Date.now();
        const before = head();
        button.click();
        page += 1;
        // the server's own paging is the stop condition; dry pages are only a
        // backstop for when meta is missing or the click never landed
        const landed = await arrive(before);
        timings.push(Date.now() - started);
        if (landed) {
          dry = 0;
        } else {
          dry += 1;
          if (dry >= 2) { page -= dry; break; }
        }
      }

      return {
        unchanged: false,
        pages: page,
        expected: lastPage(),
        total: pick('total', 'totalItems', 'total_items'),
        timings: timings,
        chapters: chapters
      };
    };

    try {
      const fast = await viaModule();
      if (fast) return JSON.stringify(fast);
    } catch (error) {
      // fall through to the walk rather than losing the series to a rotation
    }

    // only the walk needs rendered rows, so this wait sits after the fast path
    if (!(await appear())) {
      return JSON.stringify({ unchanged: false, pages: 0, expected: null, total: null, timings: [], chapters: [] });
    }

    return JSON.stringify(await viaWalk());
    """
}

// MARK: - Content

extension ComixSource {
    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL] {
        // the reader path needs the FULL series slug; resolve it from the SSR cache.
        let titleURL = descriptor.baseURL
            .appendingPathComponent("title")
            .appendingPathComponent(seriesSlug)
        let titleData = try await NetworkService().get(url: titleURL, headers: ["Referer": descriptor.referer.absoluteString])
        let detail = try Self.detail(from: String(decoding: titleData, as: UTF8.self), hid: seriesSlug)

        let readerPath = detail.url + "/" + chapterSlug
        guard let readerURL = URL(string: readerPath, relativeTo: descriptor.baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }

        // seed the reader prefs so every page eagerly loads (preload: all), wait
        // until every page has resolved (each .rpage-page has an <img> OR <canvas>
        // child — some pages render to canvas to avoid hotlinking), then extract:
        // <img> gives a src, <canvas> gives a data URL.
        let credential = try await requester.credential(for: self)
        let progress = "document.querySelectorAll('main.rpage-main .rpage-page__img').length"
        let extract = "Array.from(document.querySelectorAll('main.rpage-main .rpage-page .rpage-page__img')).map(function(el){if(el.tagName==='IMG'){return el.currentSrc||el.src;}if(el.tagName==='CANVAS'){try{return el.toDataURL('image/jpeg',0.9);}catch(e){return null;}}return null;}).filter(function(u){return u;})"

        let srcs = try await renderer.renderExtracting(
            readerURL,
            credential: credential,
            storage: [
                "reader.default.v3": Self.readerConfig,
                "read_settings_ver": "3"
            ],
            progress: progress,
            extracting: extract
        )
        return srcs.enumerated().compactMap { index, src in
            URL(string: src).map { PageURL(index: index, url: $0) }
        }
    }

    // zustand-persist envelope: the reader store expects {"state":{…},"version":…}
    private static let readerConfig = #"{"state":{"readingDirection":"ttb","pageLayout":"single","preload":"all","tapToHideMode":"double","scrollMode":"fast","scrollDistance":100,"progressBar":"left","doubleOffset":false,"stripMargin":0,"greyscale":false,"dimAmount":0,"maxImgWidth":0,"ttbZoomPercent":50,"stretch":false,"slidingAnimation":true},"version":0}"#
}

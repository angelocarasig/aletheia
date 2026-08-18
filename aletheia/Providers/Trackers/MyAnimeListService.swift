//
//  MyAnimeListService.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// rest, and unmaintained since about 2022, so most of what governs this file is
// observed rather than documented.
//
// the one that will bite: the write body must be form-encoded. send json and the
// service answers 200 OK having applied only `status` and silently discarded
// everything else - so bodies are hand-encoded here, never JSONEncoder, and the
// returned status is the only proof of what actually landed.
// see docs/features/trackers.md §5.2
struct MyAnimeListService: TrackerService, BulkListingTracker {
    let tracker: Tracker = .myAnimeList

    private let network: NetworkConfiguration

    init(network: NetworkConfiguration) {
        self.network = network
    }

    private static let fields = [
        "id", "title", "main_picture", "num_chapters", "status", "start_date",
        "nsfw", "synopsis", "media_type", "authors{first_name,last_name}",
        "alternative_titles", "genres",
        "my_list_status{status,score,num_chapters_read,start_date}",
    ].joined(separator: ",")

    // MARK: Viewer

    func viewer(token: String) async throws -> TrackerViewer {
        let user: User = try await get("/users/@me", token: token)
        return TrackerViewer(
            name: user.name,
            avatar: user.picture.flatMap(URL.init(string:)),
            // fixed at ten points for every account, so nothing is read for it
            scoreFormat: .point10
        )
    }

    // MARK: Search

    func search(_ query: String, adult: Bool, token: String) async throws -> [TrackerCandidate] {
        // q must be 3-64 characters or the request is a 400. results are
        // explicitly unordered and offsets are unstable, so this never paginates
        // expecting stability and never re-ranks what came back
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard trimmed.count >= 3 else { return [] }

        let page: Page<Node> = try await get(
            "/manga",
            token: token,
            query: [
                "q": trimmed,
                "limit": "50",
                "fields": Self.fields,
                // search is the only place nsfw is a content decision. anywhere
                // that reads the reader's own list it must be true unconditionally,
                // or entries drop out of their own list
                "nsfw": adult ? "true" : "false",
            ]
        )

        return page.data.map { node in
            let manga = node.node
            return TrackerCandidate(
                id: manga.id,
                title: manga.title,
                cover: manga.main_picture?.large.flatMap(URL.init(string:)),
                year: manga.year,
                totalChapters: manga.chapters,
                status: manga.publication,
                adult: manga.nsfw == "black",
                authors: manga.credits,
                synopsis: manga.summary,
                format: manga.shape
            )
        }
    }

    // MARK: Entry

    func entry(remoteId: Int64, token: String) async throws -> TrackerEntry {
        // my_list_status rides in the fields of the media fetch, so reading the
        // remote before a push costs no extra request
        let manga: Manga = try await get(
            "/manga/\(remoteId)",
            token: token,
            query: ["fields": Self.fields]
        )
        return manga.entry
    }

    // MARK: List

    func list(token: String) async throws -> [TrackerListEntry] {
        var request = try make(
            "/users/@me/mangalist",
            token: token,
            query: [
                "fields": "id,title,main_picture,num_chapters",
                // defaults to false and silently drops entries from the
                // reader's own list - not a content decision here, unlike on
                // search. see docs/features/trackers.md §5.2
                "nsfw": "true",
                "limit": "1000",
            ]
        )
        request.httpMethod = "GET"

        var entries: [TrackerListEntry] = []

        // offsets are documented unstable on search, but this is the one MAL
        // call meant to be walked - paging.next is an absolute, ready-to-send
        // url, so each hop is just a fresh request rather than a rebuilt one
        while true {
            let page: ListPage = try await decode(request)
            entries.append(
                contentsOf: page.data.map { item in
                    TrackerListEntry(
                        remoteId: item.node.id,
                        title: item.node.title,
                        cover: item.node.main_picture?.large.flatMap(URL.init(string:)),
                        totalChapters: item.node.chapters,
                        progress: item.list_status?.num_chapters_read ?? 0,
                        status: item.list_status?.status,
                        adult: item.node.nsfw == "black"
                    )
                })

            guard let next = page.paging?.next, let url = URL(string: next) else { break }
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Constants.Trackers.userAgent, forHTTPHeaderField: "User-Agent")
        }

        return entries
    }

    // MARK: Write

    func save(_ update: TrackerUpdate, token: String) async throws -> TrackerEntry {
        var fields: [String: String] = [:]
        if let progress = update.progress { fields["num_chapters_read"] = String(progress) }
        if let status = update.status { fields["status"] = status.mal }
        if let score = update.score { fields["score"] = String(ScoreFormat.mal(from: score)) }
        if let startDate = update.startDate {
            fields["start_date"] = Self.dateFormatter.string(from: startDate)
        }

        // omitted fields are genuinely preserved here, and unknown ones hard-400,
        // so a sparse patch is both correct and the only safe shape
        guard !fields.isEmpty else {
            return try await entry(remoteId: update.remoteId, token: token)
        }

        let status: ListStatus = try await patch(
            "/manga/\(update.remoteId)/my_list_status",
            fields: fields,
            token: token
        )

        // the media half is not returned by the patch, so it is read back rather
        // than assumed - which is also the check that the write landed
        var entry = try await entry(remoteId: update.remoteId, token: token)
        entry.status = status.status.flatMap(Status.init(mal:))
        entry.progress = status.num_chapters_read ?? entry.progress
        entry.score = status.score.flatMap { $0 > 0 ? ScoreFormat.raw(fromMal: $0) : nil }
        return entry
    }

    func delete(_ entry: TrackerEntry, token: String) async throws {
        var request = try make("/manga/\(entry.remoteId)/my_list_status", token: token)
        request.httpMethod = "DELETE"

        let (_, response) = try await send(request)
        // 404 is "not on your list", which is the state a delete was asking for
        guard (200...299).contains(response.statusCode) || response.statusCode == 404 else {
            throw Self.failure(status: response.statusCode)
        }
    }

    // MARK: Transport

    private func get<Response: Decodable>(
        _ path: String,
        token: String,
        query: [String: String] = [:]
    ) async throws -> Response {
        var request = try make(path, token: token, query: query)
        request.httpMethod = "GET"
        return try await decode(request)
    }

    private func patch<Response: Decodable>(
        _ path: String,
        fields: [String: String],
        token: String
    ) async throws -> Response {
        var request = try make(path, token: token)
        request.httpMethod = "PATCH"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields).data(using: .utf8)
        return try await decode(request)
    }

    private func make(_ path: String, token: String, query: [String: String] = [:]) throws
        -> URLRequest
    {
        guard
            var components = URLComponents(
                url: Constants.Trackers.malAPI.appending(path: path),
                resolvingAgainstBaseURL: false
            )
        else { throw TrackerError.unavailable }

        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else { throw TrackerError.unavailable }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // a user-agent containing tachiyomi or app.mihon is 307'd to an empty 204
        // by an undocumented substring blocklist. ours is checked against it
        request.setValue(Constants.Trackers.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func decode<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await send(request)

        guard (200...299).contains(response.statusCode) else {
            throw Self.failure(status: response.statusCode, body: data)
        }

        // ban and maintenance responses are html, so a decode failure here is as
        // likely to be a throttle as a schema drift - which is exactly why the
        // body is logged rather than discarded
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            TrackerLog.undecodable(
                tracker,
                Self.path(of: request),
                expected: Response.self,
                error: error,
                body: data
            )
            throw TrackerError.unavailable
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = Self.path(of: request)

        TrackerLog.sent(tracker, method, path)

        do {
            let (data, response) = try await network.send(request)
            TrackerLog.received(
                tracker, method, path, status: response.statusCode, bytes: data.count)
            return (data, response)
        } catch is CancellationError {
            throw TrackerError.cancelled
        } catch NetworkError.cancelled {
            throw TrackerError.cancelled
        } catch {
            TrackerLog.unreachable(tracker, method, path, error)
            throw TrackerError.unavailable
        }
    }

    private static func path(of request: URLRequest) -> String {
        guard let url = request.url else { return "?" }
        return url.path() + (url.query().map { "?\($0)" } ?? "")
    }

    // the 401/403 split is about whether a credential was parsed at all, not
    // about permission - so a 403 must never trigger a re-auth, since it is far
    // more often the undocumented throttle
    private static func failure(status: Int, body: Data? = nil) -> TrackerError {
        switch status {
        case 401: .reauthenticationRequired
        case 403, 504: .throttled(retryAfter: nil)
        case 404: .rejected("This title is no longer on MyAnimeList.")
        case 400:
            body.flatMap { String(data: $0, encoding: .utf8) }?.contains("invalid_content") == true
                ? .rejected(
                    "This title is still pending approval on MyAnimeList and cannot be added.")
                : .rejected("MyAnimeList refused the change.")
        default: .unavailable
        }
    }

    private static func form(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        return
            fields
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Wire

private struct User: Decodable {
    let name: String
    let picture: String?
}

private struct Page<Item: Decodable>: Decodable {
    let data: [Item]
}

private struct Node: Decodable {
    let node: Manga
}

private struct ListPage: Decodable {
    let data: [ListNode]
    let paging: Paging?

    struct Paging: Decodable { let next: String? }
}

private struct ListNode: Decodable {
    let node: Manga
    let list_status: ListStatus?
}

private struct Manga: Decodable {
    let id: Int64
    let title: String
    let main_picture: Picture?
    let num_chapters: Int?
    let status: String?
    let start_date: String?
    let nsfw: String?
    let media_type: String?
    let synopsis: String?
    let authors: [Author]?
    let my_list_status: ListStatus?
    let alternative_titles: Alternatives?
    let genres: [Genre]?

    struct Picture: Decodable { let large: String? }
    struct Genre: Decodable { let name: String }

    struct Alternatives: Decodable {
        let synonyms: [String]?
        let en: String?
        let ja: String?
    }

    // wrapped one level deeper than every other field here, and either name may
    // be missing - a mononymous artist has a first name and nothing else
    struct Author: Decodable {
        let node: Person?
        let role: String?

        struct Person: Decodable {
            let first_name: String?
            let last_name: String?
        }

        var name: String? {
            let parts = [node?.first_name, node?.last_name]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    var credits: String? {
        let names = (authors ?? []).prefix(2).compactMap(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    // manga is the assumption a reader already brings, so it earns no pill.
    // everything else is a genuine warning that this is not the thing they think
    var shape: String? {
        switch media_type {
        case "manga", nil: nil
        case "one_shot": "One-shot"
        case "light_novel": "Light novel"
        case "novel": "Novel"
        case let other: other?.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // plain text here, unlike anilist, so nothing needs flattening
    var summary: String? {
        guard let synopsis, !synopsis.isEmpty else { return nil }
        return synopsis
    }

    // 0 is the documented sentinel for unknown here rather than null, and both
    // mean the same thing to a clamp
    var chapters: Int? {
        guard let num_chapters, num_chapters > 0 else { return nil }
        return num_chapters
    }

    // dates arrive as YYYY, YYYY-MM or a full date, so the year is the prefix
    var year: Int? {
        start_date.flatMap { Int($0.prefix(4)) }
    }

    var publication: Publication {
        switch status {
        case "currently_publishing": .Ongoing
        case "finished": .Completed
        case "on_hiatus": .Hiatus
        case "discontinued": .Cancelled
        default: .Unknown
        }
    }

    // nsfw alone is not enough: it never emitted black across 636 probes, and
    // Umibe no Onnanoko carries their own Erotica genre while still reporting
    // white. the genre list is the stronger signal on this service. anything
    // else abstains rather than asserting Safe
    var rating: Classification {
        let names = Set((genres ?? []).map(\.name))
        if nsfw == "black" || names.contains("Hentai") || names.contains("Erotica") {
            return .Explicit
        }
        if nsfw == "gray" || names.contains("Ecchi") { return .Suggestive }
        return .Unknown
    }

    var pool: [String] {
        var seen = Set<String>()
        let all =
            [title, alternative_titles?.en, alternative_titles?.ja]
            .compactMap { $0 } + (alternative_titles?.synonyms ?? [])
        return all.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var entry: TrackerEntry {
        TrackerEntry(
            remoteId: id,
            title: title,
            totalChapters: chapters,
            cover: main_picture?.large.flatMap(URL.init(string:)),
            year: year,
            authors: credits,
            synopsis: summary,
            format: shape,
            publication: publication,
            adult: nsfw == "black",
            titles: pool,
            covers: [main_picture?.large.flatMap(URL.init(string:))].compactMap { $0 },
            tags: (genres ?? []).map(\.name),
            classification: rating,
            // there is no entry id - the media id addresses the entry - so
            // presence is what stands in for one
            entryId: my_list_status == nil ? nil : id,
            status: my_list_status?.status.flatMap(Status.init(mal:)),
            progress: my_list_status?.num_chapters_read ?? 0,
            score: my_list_status?.score.flatMap { $0 > 0 ? ScoreFormat.raw(fromMal: $0) : nil }
        )
    }
}

private struct ListStatus: Decodable {
    let status: String?
    let score: Int?
    let num_chapters_read: Int?
}

// MARK: - Mapping

// internal rather than private: Tracker Restore is a second caller mapping a
// freshly-pulled remote status onto a brand new series' initial Status
extension Status {
    // rereading is a boolean here rather than a status, and we have no local
    // state for it, so it is neither read nor written
    init?(mal raw: String) {
        switch raw {
        case "reading": self = .reading
        case "plan_to_read": self = .planning
        case "completed": self = .completed
        case "dropped": self = .dropped
        case "on_hold": self = .paused
        default: return nil
        }
    }
}

extension Status {
    fileprivate var mal: String {
        switch self {
        case .reading: "reading"
        case .planning: "plan_to_read"
        case .completed: "completed"
        case .dropped: "dropped"
        case .paused: "on_hold"
        }
    }
}

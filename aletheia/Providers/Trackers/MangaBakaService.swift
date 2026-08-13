//
//  MangaBakaService.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation

// rest, documented as OpenAPI 3.1, and the only one of the three that publishes a
// graded changelog. every response carries {status, data} or {status, message},
// and the message is stated to be safe to show a reader - so failures quote the
// service rather than inventing copy.
//
// three things here differ from the other two services. the token is pasted
// rather than granted, and rides in x-api-key. the media half of an entry is
// public and CDN-cached, so it is fetched without the token on purpose - only
// uncached requests count against the rate limit. and a series can answer that it
// was merged into another, which is a repair rather than an error.
// see docs/features/tracker-mangabaka.md
struct MangaBakaService: TrackerService {
    let tracker: Tracker = .mangaBaka

    private let network: NetworkConfiguration

    init(network: NetworkConfiguration) {
        self.network = network
    }

    // MARK: Viewer

    func viewer(token: String) async throws -> TrackerViewer {
        let profile: Profile = try await get("/v1/my/profile", token: token)

        // no scope check here, though the design called for one. a personal
        // access token reports scopes: [] and has full access anyway - the array
        // describes an oauth grant, which is the path this service does not give
        // us - so a guard on library.write turns away every valid token. verified
        // against a live token: empty scopes, and /v1/my/library answers 200.
        //
        // a genuinely read-only token is therefore caught at the first push, as a
        // 403 that lands on the link row with the service's own wording. see
        // docs/features/tracker-mangabaka.md §10.1
        return TrackerViewer(
            name: profile.displayName,
            // the profile carries no avatar. the oidc userinfo endpoint would,
            // but that is the grant we do not have
            avatar: nil,
            scoreFormat: profile.format
        )
    }

    // MARK: Search

    func search(_ query: String, adult: Bool, token: String) async throws -> [TrackerCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var items = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "20")
        ]

        // this endpoint returns pornographic results by default and unauthenticated,
        // so the gate is ours to apply rather than the service's to remember. it
        // validates strictly - an unknown value is a 400 rather than a silent
        // pass - and the exclusions repeat the key, which is the only form it
        // accepts. a bracketed name is an Unrecognized key
        if !adult {
            items.append(URLQueryItem(name: "not_content_rating", value: "erotica"))
            items.append(URLQueryItem(name: "not_content_rating", value: "pornographic"))
        }

        // no token: this is public and cached for an hour, and an authenticated
        // request would miss the cache it is trying to hit
        let page: Envelope<[Series]> = try await decode(make("/v1/series/search", query: items))
        return page.data.filter(\.isLive).map(\.candidate)
    }

    // MARK: Entry

    func entry(remoteId: Int64, token: String) async throws -> TrackerEntry {
        try await entry(remoteId: remoteId, token: token, following: true)
    }

    private func entry(remoteId: Int64, token: String, following: Bool) async throws -> TrackerEntry {
        // the two halves are independent: the media is public and edge-cached,
        // the listing is authenticated and never cached
        async let pending = media(remoteId)
        async let pendingListing = listing(remoteId, token: token)

        let series: Series
        do {
            series = try await pending
        } catch {
            _ = try? await pendingListing
            throw error
        }

        // a merged series names its successor rather than disappearing, and the
        // schema asks callers to update their reference. one hop only - a chain
        // that pointed back at itself would otherwise not terminate
        if following, series.state == "merged", let successor = series.merged_with, successor != remoteId {
            _ = try? await pendingListing
            return try await entry(remoteId: successor, token: token, following: false)
        }

        guard series.isLive else {
            _ = try? await pendingListing
            throw TrackerError.notFound
        }

        return series.entry(listed: try await pendingListing)
    }

    // MARK: Write

    func save(_ update: TrackerUpdate, token: String) async throws -> TrackerEntry {
        var patch = Patch()
        if let progress = update.progress {
            // an absolute ceiling of its own, separate from the series total, and
            // exceeding it rejects the whole request rather than clamping
            patch.progress_chapter = min(max(progress, 0), Self.progressCeiling)
        }
        if let status = update.status { patch.state = status.mangaBaka }
        if let score = update.score { patch.rating = min(max(score, 0), 100) }
        if let startDate = update.startDate {
            patch.start_date = Self.dateFormatter.string(from: startDate)
        }

        guard !patch.isEmpty else { return try await entry(remoteId: update.remoteId, token: token) }

        try await commit(patch, to: update.remoteId, token: token)

        // the write's body is NOT the entry, whatever the schema says it is: a
        // successful patch answers {"status":200,"data":true}. so the entry is
        // read back rather than parsed out of the response, which is what
        // myanimelist already has to do for its own reasons
        return try await entry(remoteId: update.remoteId, token: token)
    }

    // patch addresses an entry that must already exist and post creates one, so
    // each is the other's fallback: 404 means there is nothing to patch yet, and
    // 409 means there already is. one hop settles every case, and a second
    // refusal is a real failure rather than a third guess
    private func commit(_ patch: Patch, to remoteId: Int64, token: String) async throws {
        let patched = try await attempt(patch, to: remoteId, method: "PATCH", token: token)
        guard patched == 404 else { return }

        let created = try await attempt(patch, to: remoteId, method: "POST", token: token)
        guard created == 409 else { return }

        let repatched = try await attempt(patch, to: remoteId, method: "PATCH", token: token)
        guard (200...299).contains(repatched) else {
            throw TrackerError.rejected("MangaBaka would not record the change.")
        }
    }

    // returns the status instead of throwing on 404 and 409, because on this api
    // those two are how a write says "wrong verb, use the other one" - control
    // flow rather than failure. everything else still throws
    private func attempt(
        _ patch: Patch,
        to remoteId: Int64,
        method: String,
        token: String
    ) async throws -> Int {
        var request = make("/v1/my/library/\(remoteId)", token: token)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(patch)

        let (data, response) = try await perform(request)
        let status = response.statusCode

        guard (200...299).contains(status) || status == 404 || status == 409 else {
            throw Self.failure(status: status, body: data)
        }
        return status
    }

    func delete(_ entry: TrackerEntry, token: String) async throws {
        var request = make("/v1/my/library/\(entry.remoteId)", token: token)
        request.httpMethod = "DELETE"

        let (data, response) = try await perform(request)
        // 404 is "not on your list", which is the state a delete was asking for
        guard (200...299).contains(response.statusCode) || response.statusCode == 404 else {
            throw Self.failure(status: response.statusCode, body: data)
        }
    }

    // MARK: Reads

    private func media(_ remoteId: Int64) async throws -> Series {
        let envelope: Envelope<Series> = try await decode(make("/v1/series/\(remoteId)"))
        return envelope.data
    }

    // nil means the series is not on the reader's list, which is an ordinary
    // answer rather than a failure. it is a 404 and a dead token is a 401, so the
    // two are distinguishable - which is what lets the regression guard tell
    // "you have no entry" from "we could not ask"
    private func listing(_ remoteId: Int64, token: String) async throws -> Listing? {
        let request = make("/v1/my/library/\(remoteId)", token: token)
        let (data, response) = try await perform(request)

        if response.statusCode == 404 { return nil }
        guard (200...299).contains(response.statusCode) else {
            throw Self.failure(status: response.statusCode, body: data)
        }

        guard let envelope = try? JSONDecoder().decode(Envelope<Listing>.self, from: data) else {
            throw TrackerError.unavailable
        }
        return envelope.data
    }

    // MARK: Transport

    private func get<Response: Decodable>(
        _ path: String,
        token: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        let envelope: Envelope<Response> = try await decode(make(path, token: token, query: query))
        return envelope.data
    }

    // repeated keys are the only array form this api accepts, so the query is
    // built from items rather than a dictionary
    private func make(_ path: String, token: String? = nil, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(
            url: Constants.Trackers.mangaBakaAPI.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }

        var request = URLRequest(url: components?.url ?? Constants.Trackers.mangaBakaAPI.appending(path: path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Constants.Trackers.userAgent, forHTTPHeaderField: "User-Agent")
        // absent on purpose for the public endpoints: they are edge-cached, only
        // uncached requests count against the limit, and an authenticated request
        // is a guaranteed miss
        if let token { request.setValue(token, forHTTPHeaderField: "x-api-key") }
        return request
    }

    private func decode<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await perform(request)

        guard (200...299).contains(response.statusCode) else {
            throw Self.failure(status: response.statusCode, body: data)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // the error the reader sees stays vague on purpose - a coding key is
            // not something anyone can act on - so the field and the body go to
            // the log instead of being thrown away with the error
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

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = Self.path(of: request)

        TrackerLog.sent(tracker, method, path)

        do {
            let (data, response) = try await network.send(request)
            TrackerLog.received(tracker, method, path, status: response.statusCode, bytes: data.count)
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

    // path and query, never the host - the host is the same on every line and
    // the query is where a wrong filter value hides
    private static func path(of request: URLRequest) -> String {
        guard let url = request.url else { return "?" }
        return url.path() + (url.query().map { "?\($0)" } ?? "")
    }

    // the body's own message is written for readers rather than for developers,
    // so it is quoted where there is one rather than replaced with our guess at
    // what happened
    private static func failure(status: Int, body: Data?) -> TrackerError {
        let message = body
            .flatMap { try? JSONDecoder().decode(ErrorBody.self, from: $0) }
            .map(\.message)
            .flatMap { $0.isEmpty ? nil : $0 }

        switch status {
        case 401: return .reauthenticationRequired
        case 403: return .rejected(message ?? "This token is not allowed to do that.")
        case 404: return .notFound
        // only reachable if a conflict escapes commit(), which handles it as a
        // fallback rather than as an error
        case 409: return .rejected(message ?? "This series is already on your list.")
        case 429: return .throttled(retryAfter: nil)
        case 400: return .rejected(message ?? "MangaBaka refused the change.")
        default: return .unavailable
        }
    }

    // progress_chapter and progress_volume are both capped here, and the cap is
    // the request's rather than the series'
    private static let progressCeiling = 10_000

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Wire

// every response is wrapped, successes and failures alike. the parameter is not
// named Data - that would shadow Foundation's inside every member here
private struct Envelope<Payload: Decodable>: Decodable {
    let data: Payload
}

// the error half of the same envelope. named for the body rather than for the
// concept, because Failure is already the app's own error type
private struct ErrorBody: Decodable {
    let message: String
}

private struct Profile: Decodable {
    let nickname: String?
    let preferred_username: String?
    let rating_steps: Int?

    // both name fields are genuinely null on an account that has not set one, and
    // the only other identifier is an opaque string. the fallback is not the
    // service's name: that would print MangaBaka twice on a card that already
    // carries the logo
    var displayName: String {
        [nickname, preferred_username]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? "Signed in"
    }

    // a step size over 0...100 rather than a named format, and four of the five
    // land exactly on ours. the fifth, 25, is a four-step scale we have no case
    // for - it falls back to the raw hundred rather than borrowing point5, whose
    // six steps would draw a 75 as 4 against the website's 3. storage is
    // canonical either way, so this can only ever be a drawing difference
    var format: ScoreFormat {
        switch rating_steps {
        case 5: .point10Decimal
        case 10: .point10
        case 20: .point5
        default: .point100
        }
    }
}

// what the reader's list says. every field is optional because a freshly created
// entry carries almost none of them
private struct Listing: Decodable {
    let id: Int64?
    let state: String?
    let rating: Double?
    let progress_chapter: Double?
    let progress_volume: Double?
}

// the sparse patch. synthesized encoding uses encodeIfPresent for optionals, so
// an untouched field never reaches the wire - which is what makes omission mean
// "leave it alone" rather than "clear it"
private struct Patch: Encodable {
    var progress_chapter: Int?
    var state: String?
    var rating: Int?
    var start_date: String?

    var isEmpty: Bool {
        progress_chapter == nil && state == nil && rating == nil && start_date == nil
    }
}

private struct Series: Decodable {
    let id: Int64
    let state: String?
    let merged_with: Int64?
    let title: String
    let native_title: String?
    let romanized_title: String?
    let titles: [Title]?
    let cover: Cover?
    let authors: [String]?
    let artists: [String]?
    let description: String?
    let published: Published?
    let status: String?
    let content_rating: String?
    let type: String?
    let total_chapters: String?
    let tags_v2: [Tag]?

    struct Title: Decodable {
        let title: String?
    }

    struct Published: Decodable {
        let start_date: String?
    }

    struct Tag: Decodable {
        let name: String?
        let is_genre: Bool?
        let is_spoiler: Bool?
    }

    // the raw image is the one worth pooling; the sized variants are what a row
    // should draw, since a search grid has no use for a 1.6 MB png
    struct Cover: Decodable {
        let raw: Raw?
        let x250: Variant?

        struct Raw: Decodable { let url: String? }
        struct Variant: Decodable { let x2: String? }

        // the sized variant is missing on a small number of series, so the raw
        // image is the floor rather than an alternative. built through flatMap
        // rather than an empty-string default, which would hand back a url that
        // is not nil and cannot load
        var display: URL? { (x250?.x2 ?? raw?.url).flatMap(URL.init(string:)) }
        var original: URL? { raw?.url.flatMap(URL.init(string:)) }
    }

    // merged rows name a successor and deleted ones name nothing. neither should
    // be offered as something to link to
    var isLive: Bool { state == nil || state == "active" }

    // a string on the wire, and a count everywhere we use it
    var chapters: Int? {
        guard let total_chapters, let value = Int(total_chapters), value > 0 else { return nil }
        return value
    }

    var year: Int? {
        published?.start_date.flatMap { Int($0.prefix(4)) }
    }

    var credits: String? {
        var seen = Set<String>()
        let names = ((authors ?? []) + (artists ?? []))
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(2)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var summary: String? {
        guard let description, !description.isEmpty else { return nil }
        return description
    }

    // manga is the assumption a reader already brings, so it earns no pill.
    // everything else is a genuine warning that this is not the thing they think -
    // and this is the only service of the three that states it outright rather
    // than leaving it to be guessed from a title
    var shape: String? {
        switch type {
        case "manga", nil: nil
        case "oel": "OEL"
        case let other: other?.capitalized
        }
    }

    var publication: Publication {
        switch status {
        case "releasing": .Ongoing
        case "completed": .Completed
        case "hiatus": .Hiatus
        case "cancelled": .Cancelled
        // announced with nothing published. not Ongoing, which would claim
        // chapters exist, and we have no case that says otherwise
        default: .Unknown
        }
    }

    // the same four-into-three collapse mangafire already uses, so the vocabulary
    // is not this service's invention and the mapping is not a new opinion
    var classification: Classification {
        switch content_rating {
        case "safe": .Safe
        case "suggestive": .Suggestive
        case "erotica", "pornographic": .Explicit
        default: .Unknown
        }
    }

    var adult: Bool {
        content_rating == "erotica" || content_rating == "pornographic"
    }

    var pool: [String] {
        var seen = Set<String>()
        let all = [title, native_title, romanized_title].compactMap { $0 }
            + (titles ?? []).compactMap(\.title)
        return all.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // spoilers are excluded outright: a tag list is drawn without ceremony and a
    // spoiler tag is the one kind that cannot be un-read
    var labels: [String] {
        (tags_v2 ?? [])
            .filter { $0.is_spoiler != true }
            .compactMap(\.name)
            .filter { !$0.isEmpty }
    }

    var candidate: TrackerCandidate {
        TrackerCandidate(
            id: id,
            title: title,
            cover: cover?.display,
            year: year,
            totalChapters: chapters,
            status: publication,
            adult: adult,
            authors: credits,
            synopsis: summary,
            format: shape
        )
    }

    func entry(listed: Listing?) -> TrackerEntry {
        TrackerEntry(
            remoteId: id,
            title: title,
            totalChapters: chapters,
            cover: cover?.display,
            year: year,
            authors: credits,
            synopsis: summary,
            format: shape,
            publication: publication,
            adult: adult,
            titles: pool,
            covers: [cover?.original].compactMap { $0 },
            tags: labels,
            classification: classification,
            entryId: listed.map { $0.id ?? id },
            status: listed?.state.flatMap(Status.init(mangaBaka:)),
            // fractional on the wire and a position to us, so it truncates the
            // same way the watermark that produced it did
            progress: listed?.progress_chapter.map { Int($0) } ?? 0,
            // already canonical 0...100, which no other service manages
            score: listed?.rating.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        )
    }
}

// MARK: - Mapping

private extension Status {
    // seven states in, five out. rereading reads as reading rather than completed
    // for the same reason anilist's REPEATING does - demoting a finished entry is
    // the failure that rule exists to prevent - and considering is their "maybe"
    // bucket, which is a plan by another name. neither is ever written back: a
    // reader who set one on the website keeps it until they change the status
    // here, at which point they asked
    init?(mangaBaka raw: String) {
        switch raw {
        case "reading", "rereading": self = .reading
        case "plan_to_read", "considering": self = .planning
        case "completed": self = .completed
        case "dropped": self = .dropped
        case "paused": self = .paused
        default: return nil
        }
    }

    var mangaBaka: String {
        switch self {
        case .reading: "reading"
        case .planning: "plan_to_read"
        case .completed: "completed"
        case .dropped: "dropped"
        case .paused: "paused"
        }
    }
}

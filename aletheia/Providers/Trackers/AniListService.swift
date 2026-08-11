//
//  AniListService.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// one graphql endpoint for everything.
//
// three of its behaviours are undocumented and each corrupts something quietly:
// a status of COMPLETED makes the server overwrite the progress you sent with
// the media's maximum, REPEATING zeroes progress outright, and an omitted
// argument is preserved while an explicitly null one is a validation error. so
// nothing here sends a status and a progress in the same mutation expecting both
// to stick, and every write reads its own answer back.
// see docs/features/trackers.md §5.1
struct AniListService: TrackerService {
    let tracker: Tracker = .anilist

    private let network: NetworkConfiguration

    init(network: NetworkConfiguration) {
        self.network = network
    }

    // MARK: Viewer

    func viewer(token: String) async throws -> TrackerViewer {
        let query = """
        query { Viewer { id name avatar { large } mediaListOptions { scoreFormat } } }
        """

        let response: ViewerResponse = try await send(query: query, token: token)
        let viewer = response.Viewer

        return TrackerViewer(
            id: viewer.id,
            name: viewer.name,
            avatar: viewer.avatar?.large.flatMap(URL.init(string:)),
            scoreFormat: viewer.mediaListOptions?.scoreFormat ?? .point10
        )
    }

    // MARK: Search

    func search(_ query: String, adult: Bool, token: String) async throws -> [TrackerCandidate] {
        // perPage silently caps at 50, and NOVEL leaks into type: MANGA. isAdult
        // is a filter rather than a flag - false excludes the whole hentai genre,
        // and note that Ecchi survives it, which is the app-review hazard
        let document = """
        query ($q: String, $adult: Boolean) {
          Page(page: 1, perPage: 50) {
            media(search: $q, type: MANGA, isAdult: $adult, format_not_in: [NOVEL], sort: SEARCH_MATCH) {
              id
              title { romaji english native }
              coverImage { extraLarge }
              chapters
              status
              isAdult
              format
              startDate { year }
              description(asHtml: false)
              staff(perPage: 2) { edges { role node { name { full } } } }
            }
          }
        }
        """

        let variables: [String: Any] = adult
            ? ["q": query]
            : ["q": query, "adult": false]

        let response: SearchResponse = try await send(query: document, variables: variables, token: token)

        return response.Page.media.map { media in
            TrackerCandidate(
                id: media.id,
                title: media.title.preferred,
                cover: media.coverImage?.extraLarge.flatMap(URL.init(string:)),
                year: media.startDate?.year,
                totalChapters: media.chapters,
                status: media.status.publication,
                adult: media.isAdult ?? false,
                authors: media.credits,
                synopsis: media.summary,
                format: media.shape
            )
        }
    }

    // MARK: Entry

    func entry(remoteId: Int64, token: String) async throws -> TrackerEntry {
        // Media.mediaListEntry rather than the root MediaList query: that one
        // answers an untracked series with a 404 and a graphql error, so the
        // ordinary case would arrive as a failure. this fetches the media and
        // the entry in one round trip, which matters at 30 requests a minute
        let document = """
        query ($id: Int) {
          Media(id: $id, type: MANGA) {
            id
            title { romaji english native }
            chapters
            coverImage { extraLarge }
            status
            isAdult
            format
            startDate { year }
            description(asHtml: false)
            staff(perPage: 2) { edges { role node { name { full } } } }
            mediaListEntry {
              id
              status
              progress
              scoreRaw: score(format: POINT_100)
            }
          }
        }
        """

        let response: MediaResponse = try await send(
            query: document,
            variables: ["id": remoteId],
            token: token
        )
        return response.Media.entry
    }

    // MARK: Write

    func save(_ update: TrackerUpdate, token: String) async throws -> TrackerEntry {
        // SaveMediaListEntry is an upsert on mediaId alone. customLists is left
        // out entirely - it has replace semantics, so sending it on a routine
        // progress sync wipes every custom list the entry belongs to
        var arguments = ["mediaId: $mediaId"]
        var declarations = ["$mediaId: Int"]
        var variables: [String: Any] = ["mediaId": update.remoteId]

        if let progress = update.progress {
            arguments.append("progress: $progress")
            declarations.append("$progress: Int")
            variables["progress"] = progress
        }

        if let status = update.status {
            arguments.append("status: $status")
            declarations.append("$status: MediaListStatus")
            variables["status"] = status.anilist
        }

        if let score = update.score {
            arguments.append("scoreRaw: $scoreRaw")
            declarations.append("$scoreRaw: Int")
            variables["scoreRaw"] = score
        }

        if let startDate = update.startDate {
            // FuzzyDate carries no timezone, so it is built from the reader's own
            // calendar - going via utc shifts the day either side of midnight
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: startDate)
            arguments.append("startedAt: $startedAt")
            declarations.append("$startedAt: FuzzyDateInput")
            variables["startedAt"] = [
                "year": parts.year ?? 0,
                "month": parts.month ?? 0,
                "day": parts.day ?? 0
            ]
        }

        let document = """
        mutation (\(declarations.joined(separator: ", "))) {
          SaveMediaListEntry(\(arguments.joined(separator: ", "))) {
            id
            status
            progress
            scoreRaw: score(format: POINT_100)
            media { id title { romaji english native } chapters }
          }
        }
        """

        let response: SaveResponse = try await send(query: document, variables: variables, token: token)
        return response.SaveMediaListEntry.entry
    }

    func delete(_ entry: TrackerEntry, token: String) async throws {
        // takes the list-entry id, not the media id. an entry we never saw an id
        // for is already absent as far as the service is concerned
        guard let entryId = entry.entryId else { return }

        let document = "mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }"
        let _: DeleteResponse = try await send(
            query: document,
            variables: ["id": entryId],
            token: token
        )
    }

    // MARK: Transport

    private func send<Response: Decodable>(
        query: String,
        variables: [String: Any] = [:],
        token: String
    ) async throws -> Response {
        var request = URLRequest(url: Constants.Trackers.anilistAPI)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["query": query]
        if !variables.isEmpty { body["variables"] = variables }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await network.send(request)
        } catch is CancellationError {
            throw TrackerError.cancelled
        } catch NetworkError.cancelled {
            throw TrackerError.cancelled
        } catch {
            throw TrackerError.unavailable
        }

        if response.statusCode == 429 {
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw TrackerError.throttled(retryAfter: retry)
        }

        let envelope = try? JSONDecoder().decode(Envelope<Response>.self, from: data)

        if let error = envelope?.errors?.first {
            // a dead token is an http 400 with the body {"message":"Invalid
            // token","status":400}. probed 2026-08-10, along with the case this
            // must not be confused with: a 401 "Unauthorized." means the header
            // never arrived at all, which is our bug - re-authenticating on it
            // would sign the reader out for a mistake they did not make
            if error.status == 400, error.message.localizedCaseInsensitiveContains("token") {
                throw TrackerError.reauthenticationRequired
            }
            throw TrackerError.rejected(error.message)
        }

        guard (200...299).contains(response.statusCode) else {
            throw TrackerError.unavailable
        }

        guard let data = envelope?.data else { throw TrackerError.unavailable }
        return data
    }
}

// MARK: - Wire

private struct Envelope<Data: Decodable>: Decodable {
    let data: Data?
    let errors: [GraphQLError]?

    struct GraphQLError: Decodable {
        let message: String
        let status: Int?
    }
}

private struct ViewerResponse: Decodable {
    let Viewer: Viewer

    struct Viewer: Decodable {
        let id: Int64
        let name: String
        let avatar: Avatar?
        let mediaListOptions: Options?

        struct Avatar: Decodable { let large: String? }
        struct Options: Decodable { let scoreFormat: ScoreFormat? }
    }
}

private struct SearchResponse: Decodable {
    let Page: Page

    struct Page: Decodable { let media: [Media] }
}

private struct MediaResponse: Decodable {
    let Media: Media
}

private struct SaveResponse: Decodable {
    let SaveMediaListEntry: ListEntry
}

private struct DeleteResponse: Decodable {
    let DeleteMediaListEntry: Deleted?

    struct Deleted: Decodable { let deleted: Bool? }
}

private struct Media: Decodable {
    let id: Int64
    let title: Title
    let coverImage: Cover?
    let chapters: Int?
    let status: String?
    let isAdult: Bool?
    let format: String?
    let startDate: FuzzyDate?
    let mediaListEntry: Listing?
    let description: String?
    let staff: Staff?

    struct Cover: Decodable { let extraLarge: String? }
    struct FuzzyDate: Decodable { let year: Int? }

    struct Staff: Decodable {
        let edges: [Edge]?

        struct Edge: Decodable {
            let role: String?
            let node: Person?

            struct Person: Decodable {
                let name: Name?
                struct Name: Decodable { let full: String? }
            }
        }
    }

    // the role rides along because "Story & Art" and "Story" are different
    // people on a third of these, and a bare pair of names does not say which
    var credits: String? {
        let names = (staff?.edges ?? []).compactMap { $0.node?.name?.full }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    // NOVEL is filtered out of the query, so what is left is the distinction
    // between a serialised work and a one-shot - and MANGA is the default the
    // reader already assumes, so it says nothing worth a pill
    var shape: String? {
        switch format {
        case "ONE_SHOT": "One-shot"
        case "NOVEL": "Novel"
        case "MANGA": nil
        default: format?.capitalized
        }
    }

    // anilist's description is not html but is not plain either - it carries
    // <br> and <i> and the occasional spoiler tag. the same parser the sources
    // use flattens it, and a row wants one paragraph rather than the whole thing
    var summary: String? {
        guard let description, !description.isEmpty else { return nil }
        let text = HTMLMarkdown.from(description)
        return text.isEmpty ? nil : text
    }

    var entry: TrackerEntry {
        TrackerEntry(
            remoteId: id,
            title: title.preferred,
            totalChapters: chapters,
            cover: coverImage?.extraLarge.flatMap(URL.init(string:)),
            year: startDate?.year,
            authors: credits,
            synopsis: summary,
            format: shape,
            publication: status.publication,
            adult: isAdult ?? false,
            entryId: mediaListEntry?.id,
            status: mediaListEntry?.status.flatMap(Status.init(anilist:)),
            progress: mediaListEntry?.progress ?? 0,
            score: mediaListEntry?.score
        )
    }
}

// the entry as it hangs off a media, which is the only place a query asks for
// one. deliberately not the same type as the mutation's answer - graphql nests
// them the other way round there, and one type doing both is a recursive struct
private struct Listing: Decodable {
    let id: Int64?
    let status: String?
    let progress: Int?
    let scoreRaw: Int?

    var score: Int? {
        scoreRaw.flatMap { $0 > 0 ? $0 : nil }
    }
}

private struct ListEntry: Decodable {
    let id: Int64?
    let status: String?
    let progress: Int?
    let scoreRaw: Int?
    let media: SavedMedia?

    struct SavedMedia: Decodable {
        let id: Int64
        let title: Title
        let chapters: Int?
    }

    var entry: TrackerEntry {
        TrackerEntry(
            remoteId: media?.id ?? 0,
            title: media?.title.preferred ?? "",
            totalChapters: media?.chapters,
            entryId: id,
            status: status.flatMap(Status.init(anilist:)),
            progress: progress ?? 0,
            score: scoreRaw.flatMap { $0 > 0 ? $0 : nil }
        )
    }
}

private struct Title: Decodable {
    let romaji: String?
    let english: String?
    let native: String?

    // english is null far more often than its prominence suggests
    var preferred: String {
        english ?? romaji ?? native ?? "Untitled"
    }
}

// MARK: - Mapping

private extension Optional where Wrapped == String {
    var publication: Publication {
        switch self {
        case "RELEASING": .Ongoing
        case "FINISHED": .Completed
        case "HIATUS": .Hiatus
        case "CANCELLED": .Cancelled
        default: .Unknown
        }
    }
}

private extension Status {
    // REPEATING has no local equivalent and is deliberately not completed: an
    // entry the reader set to rereading on the website should keep syncing
    init?(anilist raw: String) {
        switch raw {
        case "CURRENT", "REPEATING": self = .reading
        case "PLANNING": self = .planning
        case "COMPLETED": self = .completed
        case "DROPPED": self = .dropped
        case "PAUSED": self = .paused
        default: return nil
        }
    }
}

private extension Status {
    var anilist: String {
        switch self {
        case .reading: "CURRENT"
        case .planning: "PLANNING"
        case .completed: "COMPLETED"
        case .dropped: "DROPPED"
        case .paused: "PAUSED"
        }
    }
}

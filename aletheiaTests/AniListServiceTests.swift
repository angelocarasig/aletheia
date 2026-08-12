//
//  AniListServiceTests.swift
//  aletheiaTests
//
//  Created by Angelo Carasig on 12/8/2026.
//

import Testing
import Foundation
@testable import aletheia

// the transport reads one body twice - once for the payload, once for the
// errors - and these pin why. graphql sends both halves together, so decoding
// them as one unit meant a payload that did not fit the response type silently
// destroyed the reason beside it. all four bodies below were probed live
// against graphql.anilist.co on 2026-08-12.
// see docs/features/trackers.md 5.1
@Suite("AniListService")
struct AniListServiceTests {

    private struct Stub: NetworkConfiguration {
        let status: Int
        let body: String

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(body.utf8), response)
        }

        func get<Model: Decodable>(url: URL, headers: [String: String]?) async throws -> Model {
            throw NetworkError.offline
        }

        func get(url: URL, headers: [String: String]?) async throws -> Data {
            throw NetworkError.offline
        }

        func post<Request: Encodable, Response: Decodable>(
            url: URL,
            body: Request,
            headers: [String: String]?
        ) async throws -> Response {
            throw NetworkError.offline
        }
    }

    private func service(status: Int, body: String) -> AniListService {
        AniListService(network: Stub(status: status, body: body))
    }

    // the case that produced the report. an id anilist does not have answers
    // 404 with a null Media, which MediaResponse cannot decode - so the whole
    // envelope failed, the error went with it, and the reader was told the
    // service was down. it had answered, clearly, on the first attempt
    @Test("a missing entry is not found, not an outage")
    func missingEntry() async throws {
        let subject = service(
            status: 404,
            body: #"{"errors":[{"message":"Not Found.","status":404}],"data":{"Media":null}}"#
        )

        await #expect(throws: TrackerError.notFound) {
            _ = try await subject.entry(remoteId: 999_999_999, token: "t")
        }
    }

    @Test("a missing entry is not offered a retry")
    func missingEntryIsNotRetryable() {
        #expect(TrackerError.notFound.isRetryable == false)
        // but it must not halt the lane the way an auth failure does
        #expect(TrackerError.notFound.isTerminal == false)
    }

    @Test("a search with no matches is an empty list")
    func emptySearch() async throws {
        let subject = service(status: 200, body: #"{"data":{"Page":{"media":[]}}}"#)

        let results = try await subject.search("zzqqxx nonexistent", adult: false, token: "t")
        #expect(results.isEmpty)
    }

    @Test("a search that matched reads its data")
    func populatedSearch() async throws {
        let subject = service(
            status: 200,
            body: #"{"data":{"Page":{"media":[{"id":30013,"title":{"romaji":"One Piece"}}]}}}"#
        )

        let results = try await subject.search("one piece", adult: false, token: "t")
        #expect(results.count == 1)
        #expect(results.first?.id == 30013)
    }

    // a dead token is also a 400 with no usable data, and degrading it to
    // unavailable would leave the reader signed out with nothing telling them
    @Test("a dead token still asks for re-authentication")
    func deadToken() async throws {
        let subject = service(
            status: 400,
            body: #"{"errors":[{"message":"Invalid token","status":400}]}"#
        )

        await #expect(throws: TrackerError.reauthenticationRequired) {
            _ = try await subject.search("anything", adult: false, token: "dead")
        }
    }

    // the error's own words survive the payload failing to decode, which is
    // what the second pass buys
    @Test("an error with no usable data speaks for itself")
    func errorWithoutData() async throws {
        let subject = service(
            status: 400,
            body: #"{"errors":[{"message":"validation error","status":400}],"data":null}"#
        )

        await #expect(throws: TrackerError.rejected("validation error")) {
            _ = try await subject.search("anything", adult: false, token: "t")
        }
    }
}

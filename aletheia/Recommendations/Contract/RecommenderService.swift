//
//  RecommenderService.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import CryptoKit
import Foundation
import Tagged

// what the app asks a recommender for. built from a series' title pool and its
// tags - never a SeriesRecord, so the engine has no route to the database and the
// policy for choosing a seed stays outside it
// Equatable because a caller re-applies on every database change and the answer
// cannot move unless the payload does. without it a 53ms query runs on every
// reader progress tick
struct Payload: Sendable, Equatable {
    // the whole pool, not just the primary - names vote, see AliasIndex.tally
    var titles: [String] = []
    var tags: [String] = []
    // present when the reader has linked this series to MangaBaka, whose remote
    // id IS the catalogue id. an exact hit that skips name resolution entirely
    var catalogId: CatalogID?

    // below: only used by a recommender with a live-compute path (v01 has
    // none, so these sit unread there) - an unresolved title with no rail to
    // fall back on, scored from what this pool actually has
    var synopsis: String = ""
    // the earliest chapter's publishedDate, not the title's real first-
    // publication year - a scanlation release date, not a launch date. no
    // schema carries a real one, so this is the closest proxy already sitting
    // in the database rather than a new field
    var year: Int?
    // the already-downloaded local cover, never fetched here - a recommender
    // reads from disk if present and drops the block otherwise, it does not
    // reach out to the network on a screen this is only an addition to
    var cover: URL?
    // series format (manga/manhwa/manhua/...): no source in this app reports
    // it today, so there is nowhere to source this from - TBD, left absent
    // until that data exists rather than guessed at
}

extension Payload {
    // a stable identity for exactly what was fed to a query. persisted
    // fingerprints can't use Swift's Hasher - it's randomised per process, so a
    // fingerprint written today would never match itself after the next launch.
    // control-character separators avoid the ["ab","c"] vs ["a","bc"] collision
    // a plain "," join would risk against a title that happens to contain one
    var fingerprint: String {
        var input = titles.joined(separator: "\u{1}")
        input += "\u{0}" + tags.joined(separator: "\u{1}")
        input += "\u{0}" + (catalogId.map { String($0.rawValue) } ?? "")
        input += "\u{0}" + synopsis
        input += "\u{0}" + (year.map(String.init) ?? "")
        input += "\u{0}" + (cover?.absoluteString ?? "")

        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct RecommenderDescriptor: Sendable, Hashable {
    let slug: String
    let name: String
    let formatVersion: Int
    let titleCount: Int
    // false for v01: the text encoder was not exported, so an unresolved payload
    // is scored on tags alone
    let encodesText: Bool
    let hasMetadata: Bool
}

protocol RecommenderService: Sendable {
    var descriptor: RecommenderDescriptor { get async }

    // load, and pay the paging cost up front. loading itself is 22ms - the part
    // worth moving is the ~190ms of page faults the first query takes touching
    // 116 MB of embeddings for the first time, which otherwise lands on whichever
    // series the reader opens first
    //
    // never throws. recommendations are an addition to a screen, so a model that
    // will not load costs a section rather than a launch
    func warm() async

    func recommend(
        _ payload: Payload,
        ceiling: ContentCeiling,
        formats: Set<CatalogFormat>,
        limit: Int
    ) async throws -> RecommendationSet
}

typealias Recommender = any RecommenderService

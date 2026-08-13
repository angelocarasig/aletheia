//
//  Tracker.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// an external list service. the raw value is the wire slug in three places at
// once - the stored column, the keychain account key, and the oauth redirect
// path - so it is a contract rather than a display detail
enum Tracker: String, Codable, Sendable, CaseIterable, Identifiable {
    case anilist
    case myAnimeList = "myanimelist"
    case mangaBaka = "mangabaka"

    var id: String { rawValue }

    // whether a linked account's description may be kept in our own pool.
    // myanimelist's api agreement reaches "any other data communicated from the
    // API" and adds a 24-hour duty to propagate anything they retract, which a
    // local database has no mechanism to hear - so their prose is shown live and
    // never stored. facts travel either way; only the authored paragraph does
    // not. see docs/features/tracker-metadata.md §5.4
    //
    // mangabaka aggregates prose from six sites, so some of it started at
    // myanimelist - but nothing in its terms asks for retraction to propagate,
    // and the clause that does bind us is NonCommercial. true is therefore a fact
    // about this app rather than about the service, and is one of the things to
    // revisit if it is ever distributed commercially.
    // see docs/features/tracker-mangabaka.md §7.3
    var storesProse: Bool {
        switch self {
        case .anilist: true
        case .myAnimeList: false
        case .mangaBaka: true
        }
    }

    var name: String {
        switch self {
        case .anilist: "AniList"
        case .myAnimeList: "MyAnimeList"
        case .mangaBaka: "MangaBaka"
        }
    }

    // the full-colour brand tile, drawn untinted. the *Mark variants alongside
    // are template-rendered for surfaces that want a tintable glyph
    var icon: String {
        switch self {
        case .anilist: "AniList"
        case .myAnimeList: "MyAnimeList"
        case .mangaBaka: "MangaBaka"
        }
    }

    var mark: String { icon + "Mark" }

    // where its entries live. the one place the domain is written down, so
    // building a link and reading one back can never disagree
    var host: String {
        switch self {
        case .anilist: "anilist.co"
        case .myAnimeList: "myanimelist.net"
        case .mangaBaka: "mangabaka.org"
        }
    }

    // the other two file an entry under /manga/<id>; mangabaka puts a series at
    // the root. remoteId(in:) needs no matching branch - it takes the first
    // all-digit path component after the host, which is the id in both shapes
    func url(for remoteId: Int64) -> URL? {
        switch self {
        case .anilist, .myAnimeList: URL(string: "https://\(host)/manga/\(remoteId)")
        case .mangaBaka: URL(string: "https://\(host)/\(remoteId)")
        }
    }

    // the entry id in a pasted link, or nil if the link is not this service's.
    // checked against this tracker rather than any of them, or a link pasted
    // into the wrong sheet resolves to a real entry on the wrong service.
    //
    // a URL only. a bare number is a title as often as it is an id - "20",
    // "86", "1984" are all real series - and treating one as an id turned a
    // search for them into a single wrong result with no way to tell why
    func remoteId(in text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(host) else { return nil }

        // .../manga/101177/kanojo-mo-kanojo - the id is the first all-digit
        // component after the host, never the slug beside it
        return trimmed
            .split(whereSeparator: { "/?#".contains($0) })
            .compactMap { Int64($0) }
            .first
    }

    // whether any service claims this link, for a field that has to decide
    // between searching and resolving before a service is chosen
    static func remoteId(in text: String) -> (tracker: Tracker, id: Int64)? {
        for tracker in allCases {
            if let id = tracker.remoteId(in: text) { return (tracker, id) }
        }
        return nil
    }

    // anilist reads its score scale from the account and can be any of five;
    // myanimelist is fixed at ten points for everyone. mangabaka is per-account
    // too, as a step size over 0...100 rather than a named format
    var fixedScoreFormat: ScoreFormat? {
        switch self {
        case .anilist: nil
        case .myAnimeList: .point10
        case .mangaBaka: nil
        }
    }

    // whether signing in is a browser round trip or a pasted token. mangabaka
    // publishes no public-client oauth registration, so its reader creates a
    // personal access token and pastes it - which needs no callback, no refresh
    // and no client id, and lands in the same credential as the other two
    var usesPastedToken: Bool {
        switch self {
        case .anilist, .myAnimeList: false
        case .mangaBaka: true
        }
    }
}

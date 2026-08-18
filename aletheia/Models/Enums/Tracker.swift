//
//  Tracker.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// raw value is the wire slug in three places at once - the stored column, the
// keychain account key, and the oauth redirect path - not a display detail
enum Tracker: String, Codable, Sendable, CaseIterable, Identifiable {
    case anilist
    case myAnimeList = "myanimelist"
    case mangaBaka = "mangabaka"

    var id: String { rawValue }

    // myanimelist's api agreement adds a 24-hour duty to propagate any
    // retraction, which a local database can't hear - so their prose is shown
    // live, never stored. see docs/features/tracker-metadata.md §5.4
    //
    // mangabaka's terms don't require retraction propagation, but its
    // NonCommercial clause is what binds us here - revisit if ever
    // distributed commercially. see docs/features/tracker-mangabaka.md §7.3
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

    // full-colour brand tile, drawn untinted - *Mark variants are
    // template-rendered for surfaces that want a tintable glyph
    var icon: String {
        switch self {
        case .anilist: "AniList"
        case .myAnimeList: "MyAnimeList"
        case .mangaBaka: "MangaBaka"
        }
    }

    var mark: String { icon + "Mark" }

    // the one place the domain is written down, so building a link and
    // reading one back can never disagree
    var host: String {
        switch self {
        case .anilist: "anilist.co"
        case .myAnimeList: "myanimelist.net"
        case .mangaBaka: "mangabaka.org"
        }
    }

    // the other two file an entry under /manga/<id>; mangabaka puts a series
    // at the root - remoteId(in:) needs no matching branch since it takes the
    // first all-digit path component after the host either way
    func url(for remoteId: Int64) -> URL? {
        switch self {
        case .anilist, .myAnimeList: URL(string: "https://\(host)/manga/\(remoteId)")
        case .mangaBaka: URL(string: "https://\(host)/\(remoteId)")
        }
    }

    // a URL only - a bare number is a title as often as it is an id ("20",
    // "86", "1984" are all real series), and treating one as an id once
    // turned a search for them into a single wrong result with no way to
    // tell why
    func remoteId(in text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(host) else { return nil }

        // .../manga/101177/kanojo-mo-kanojo - the id is the first all-digit
        // component after the host, never the slug beside it
        return
            trimmed
            .split(whereSeparator: { "/?#".contains($0) })
            .compactMap { Int64($0) }
            .first
    }

    static func remoteId(in text: String) -> (tracker: Tracker, id: Int64)? {
        for tracker in allCases {
            if let id = tracker.remoteId(in: text) { return (tracker, id) }
        }
        return nil
    }

    // anilist reads its score scale from the account, any of five; myanimelist
    // is fixed at ten points for everyone; mangabaka is per-account too, as a
    // step size over 0...100 rather than a named format
    var fixedScoreFormat: ScoreFormat? {
        switch self {
        case .anilist: nil
        case .myAnimeList: .point10
        case .mangaBaka: nil
        }
    }

    // mangabaka publishes no public-client oauth registration, so its reader
    // pastes a personal access token instead - no callback, no refresh, no
    // client id, and it lands in the same credential store as the other two
    var usesPastedToken: Bool {
        switch self {
        case .anilist, .myAnimeList: false
        case .mangaBaka: true
        }
    }
}

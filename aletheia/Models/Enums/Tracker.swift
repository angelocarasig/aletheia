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

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anilist: "AniList"
        case .myAnimeList: "MyAnimeList"
        }
    }

    // the full-colour brand tile, drawn untinted. the *Mark variants alongside
    // are template-rendered for surfaces that want a tintable glyph
    var icon: String {
        switch self {
        case .anilist: "AniList"
        case .myAnimeList: "MyAnimeList"
        }
    }

    var mark: String { icon + "Mark" }

    // where its entries live. the one place the domain is written down, so
    // building a link and reading one back can never disagree
    var host: String {
        switch self {
        case .anilist: "anilist.co"
        case .myAnimeList: "myanimelist.net"
        }
    }

    func url(for remoteId: Int64) -> URL? {
        URL(string: "https://\(host)/manga/\(remoteId)")
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
    // myanimelist is fixed at ten points for everyone
    var fixedScoreFormat: ScoreFormat? {
        switch self {
        case .anilist: nil
        case .myAnimeList: .point10
        }
    }
}

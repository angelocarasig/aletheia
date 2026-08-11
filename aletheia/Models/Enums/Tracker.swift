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

    func url(for remoteId: Int64) -> URL? {
        switch self {
        case .anilist: URL(string: "https://anilist.co/manga/\(remoteId)")
        case .myAnimeList: URL(string: "https://myanimelist.net/manga/\(remoteId)")
        }
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

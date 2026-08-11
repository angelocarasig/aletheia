//
//  Keychain.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

/// composable keychain namespaces - each a KeychainStore scoped to its own service.
///
///     Keychain.sources.save(credential, account: "mangafire")
///     Keychain.trackers.load(Token.self, account: "anilist")
enum Keychain {
    static let sources = KeychainStore(service: "moe.aletheia.sources")
    static let trackers = KeychainStore(service: "moe.aletheia.trackers")
}

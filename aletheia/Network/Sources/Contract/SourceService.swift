//
//  SourceService.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

protocol SourceService: Sendable {
    var descriptor: SourceDescriptor { get }

    var presets: [SourcePreset] { get }

    func search(_ query: SearchQuery) async throws -> SearchPage<SeriesStub>

    func details(seriesSlug: String) async throws -> SeriesDetail

    // an empty list means the series has none - throwing is the only way to say
    // "unknown". a source that can check cheaply whether anything changed
    // conforms to RevalidatingSource as well
    func chapters(seriesSlug: String) async throws -> [ChapterEntry]

    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL]

    var pingURL: URL { get }
}

extension SourceService {
    var presets: [SourcePreset] { [] }

    // headers for a request made on the source's behalf outside its own code -
    // page images and cover art. read from the keychain rather than through
    // AuthRequester: fetching bytes is not the place to trigger an interactive
    // challenge, since the caller just finished a source call that refreshed it
    var requestHeaders: [String: String] {
        var headers = [
            "Referer": descriptor.referer.absoluteString,
            "User-Agent": Constants.Network.userAgent,
        ]

        guard let source = self as? any AuthenticatingSource,
            let credential = try? Keychain.sources.load(
                SourceCredential.self,
                account: source.descriptor.slug
            )
        else { return headers }

        headers["User-Agent"] = credential.userAgent

        for (key, value) in credential.headers ?? [:] {
            headers[key] = value
        }

        if !credential.cookies.isEmpty {
            headers["Cookie"] = credential.cookies
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
        }

        return headers
    }

    func resolvedSort(for query: SearchQuery) -> SortSelection {
        query.sort ?? descriptor.supportedSort.defaultSelection
    }

    // shut is the default, and shut must mean the request *excludes* adult
    // content rather than omitting the parameter - hosts differ on what they
    // send when asked nothing, and most of them differ from what this app wants
    func allowsAdult(for query: SearchQuery) -> Bool {
        // adultOnly sources have no option to tick, since opening one is the
        // request - previously gated on filters only, so their covers never
        // blurred and the grid never offered a reveal
        guard !descriptor.adultOnly else { return true }

        let chosen = query.filters.flatMap { selection -> [(filter: String, option: String)] in
            switch selection {
            case .select(let id, let optionID):
                return [(id, optionID)]
            case .multiSelect(let id, let included, _):
                return included.map { (id, $0) }
            case .text, .number:
                return []
            }
        }

        return chosen.contains { pair in
            descriptor.supportedFilters.contains { filter in
                switch filter {
                case .select(let id, _, let options), .multiSelect(let id, _, let options, _):
                    id == pair.filter
                        && options.contains {
                            $0.id == pair.option && $0.sensitivity == .adult
                        }
                case .text, .number:
                    false
                }
            }
        }
    }
}

typealias Source = any SourceService

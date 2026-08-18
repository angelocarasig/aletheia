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

    // an empty list means the series has none. throwing is the only way to say
    // nothing at all, and the only answer that leaves the stored list unknown.
    // a source that can check cheaply whether anything changed conforms to
    // RevalidatingSource as well
    func chapters(seriesSlug: String) async throws -> [ChapterEntry]

    func content(seriesSlug: String, chapterSlug: String) async throws -> [PageURL]

    // what a health check hits. defaults to the site root, but a source whose
    // root is gated (an API behind Cloudflare, say) points this at a cheap
    // always-reachable endpoint instead - the root would read as down
    var pingURL: URL { get }
}

extension SourceService {
    // a source with nothing to show on its home screen is the normal case, so
    // it is the default rather than something every source has to write out
    var presets: [SourcePreset] { [] }

    // what the source itself would send, for any request made on its behalf that
    // does not go through the source's own code - page images and cover art. an
    // image host behind cloudflare answers a bare request differently from a
    // browser's, and a 200 text/html interstitial is not an image, so a missing
    // cookie header surfaces as "couldn't save image" rather than as a challenge.
    //
    // read from the keychain rather than through AuthRequester: the caller has
    // just finished a source call that refreshed it, and fetching bytes is not
    // the place to trigger an interactive challenge
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

    // a query without an explicit sort falls back to the descriptor's declared
    // search default - the source's best match - so every search() resolves the
    // same way instead of each source inventing its own fallback
    func resolvedSort(for query: SearchQuery) -> SortSelection {
        query.sort ?? descriptor.supportedSort.defaultSelection
    }

    // the gate. adult results reach a search only because the reader ticked an
    // option the source itself declared `.adult`, so the answer is derived once
    // here rather than four times over - `FilterSelection` carries option ids
    // alone, and resolving them back to options needs the descriptor.
    //
    // shut is the default, and shut must mean the request *excludes* adult
    // content rather than omitting the parameter: every host has an opinion about
    // what to send when asked nothing, and three of the four differ from ours.
    //
    // this shapes the request. what a stub is stamped with is a separate question
    // the source answers for itself - from the item where it has a per-item
    // field, from the request it just built where it does not
    func allowsAdult(for query: SearchQuery) -> Bool {
        // a source that is adult by definition has no option to tick - opening it
        // is the request. gating it on the filters left it stamping nothing as
        // adult, so its covers never blurred and its grid never offered a reveal
        guard !descriptor.adultOnly else { return true }

        // excluding an option is not a request for it, so only the included side
        // counts. text and number filters carry no options and never qualify
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

//
//  AnyModifier+Headers.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import Kingfisher

extension AnyModifier {
    // most sources reject image requests that do not carry their own referer,
    // and a cloudflare-fronted one wants the pinned agent and its cookies too.
    // headers ride here rather than in the processor, so a credential refresh
    // does not change the cache key and orphan every page already on disk
    // covers and search thumbnails only ever needed the one header
    static func referer(_ url: URL?) -> AnyModifier {
        headers(url.map { ["Referer": $0.absoluteString] } ?? [:])
    }

    static func headers(_ headers: [String: String]) -> AnyModifier {
        AnyModifier { request in
            guard !headers.isEmpty else { return request }

            var request = request
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            return request
        }
    }
}

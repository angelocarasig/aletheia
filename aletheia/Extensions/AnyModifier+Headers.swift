//
//  AnyModifier+Headers.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import Kingfisher

extension AnyModifier {
    // headers ride here rather than in the processor, so a credential refresh
    // does not change kingfisher's cache key and orphan every page on disk
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

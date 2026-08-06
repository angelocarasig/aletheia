//
//  SourceDescriptor.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation
import struct SwiftUI.ImageResource

struct SourceDescriptor: Sendable, Hashable {
    let slug: String
    let name: String
    let description: String
    let icon: ImageResource
    let languages: [LanguageCode]
    let baseURL: URL
    let referer: URL
    let supportedFilters: [SourceFilter]
    let supportedSorts: [SourceFilter.Sort]
}

extension SourceDescriptor {
    var fingerprint: String {
        let parts: [String] = [
            slug,
            name,
            baseURL.absoluteString,
            referer.absoluteString,
            languages.map(\.rawValue).sorted().joined(separator: ","),
            supportedFilters.map(\.fingerprint).joined(separator: "|"),
            supportedSorts.map(\.fingerprint).joined(separator: "|")
        ]

        return Checksum.hex(parts.joined(separator: "\u{1F}"))
    }
}

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
    let supportedSort: SourceFilter.Sort

    /// the whole catalogue is pornographic, not merely capable of it - exempt from
    /// the tick gate, stamps every stub `adult`, and lets the blur preference do
    /// its work. code-defined and never persisted; `SourceRecord` stores what
    /// outlives the code, and this ships and dies with the source.
    var adultOnly: Bool = false
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
            supportedSort.fingerprint,
            adultOnly ? "adult" : "mixed",
        ]

        return Checksum.hex(parts.joined(separator: "\u{1F}"))
    }
}

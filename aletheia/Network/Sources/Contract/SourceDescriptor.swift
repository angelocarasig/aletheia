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
    // exactly one. every source can order its results somehow, so this is
    // required rather than optional - and no source has ever declared a second
    // axis, which is why it is not a collection either
    let supportedSort: SourceFilter.Sort

    /// the whole catalogue is pornographic, not merely capable of it.
    ///
    /// such a source is exempt from the tick gate - the gate separates adult from
    /// clean *within* a mixed catalogue, and one with nothing to separate has no
    /// filter that could open it. it stamps every stub `adult` and lets the blur
    /// preference do its work. that is rung 1 of the ladder with a constant
    /// answer, not rung 3: it knows, and the answer is always yes.
    ///
    /// the field exists for the decisions a stub cannot answer because they
    /// happen before one exists - chiefly whether global search fans out to it at
    /// all. code-defined and never persisted; `SourceRecord` stores what outlives
    /// the code, and this ships and dies with the source.
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
            adultOnly ? "adult" : "mixed"
        ]

        return Checksum.hex(parts.joined(separator: "\u{1F}"))
    }
}

//
//  ReaderImage.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import UIKit
import Kingfisher

// the cell and the prefetcher MUST build their options the same way. a
// processor difference changes the cache key, so prefetched pages land under a
// key the cell never looks up and every prefetch is wasted
enum ReaderImage {
    // a page is a full-bleed bitmap on a device screen, not a thumbnail.
    // decoding at source resolution is what puts a reader into jetsam - a
    // 1400x2000 page is ~11mb resident once decoded
    static func options(referer: URL?, width: CGFloat) -> KingfisherOptionsInfo {
        let limit = max(width, 1) * UIScreen.main.scale

        return [
            .backgroundDecode,
            .downsamplingImageProcessor(size: CGSize(width: limit, height: limit)),
            .scaleFactor(UIScreen.main.scale),
            .requestModifier(AnyModifier.referer(referer)),
            .cacheOriginalImage
        ]
    }
}

private extension KingfisherOptionsInfoItem {
    // DownsamplingImageProcessor keys on its size, so both call sites derive it
    // from the same number and stay cache-compatible
    static func downsamplingImageProcessor(size: CGSize) -> KingfisherOptionsInfoItem {
        .processor(DownsamplingImageProcessor(size: size))
    }
}

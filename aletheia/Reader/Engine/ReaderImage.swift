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
    // scale comes from whatever view is asking. UIScreen.main is deprecated on
    // iOS 26 and was never right anyway - the value that matters is the one for
    // the display this reader is actually on
    static func options(
        headers: [String: String],
        width: CGFloat,
        scale: CGFloat
    ) -> KingfisherOptionsInfo {
        let scale = max(scale, 1)

        // POINTS, not pixels. DownsamplingImageProcessor hands this straight to
        // downsampledImage(data:to:scale:), which multiplies by the scale factor
        // itself - passing width * scale asked for three times the dimension and
        // nine times the pixels on a 3x device
        let limit = max(width, 1)

        return [
            .backgroundDecode,
            .downsamplingImageProcessor(size: CGSize(width: limit, height: limit)),
            .scaleFactor(scale),
            .requestModifier(AnyModifier.headers(headers)),
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

//
//  ReaderImage.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Kingfisher
import UIKit

// the cell and the prefetcher MUST build their options the same way. a
// processor difference changes the cache key, so prefetched pages land under a
// key the cell never looks up and every prefetch is wasted
enum ReaderImage {
    // a page is a full-bleed bitmap on a device screen, not a thumbnail.
    // decoding at source resolution is what puts a reader into jetsam - a
    // 1400x2000 page is ~11mb resident once decoded.
    //
    // scale comes from whatever view is asking. UIScreen.main is deprecated on
    // iOS 26 and was never right anyway - the value that matters is the one for
    // the display this reader is actually on
    static func options(
        headers: [String: String],
        width: CGFloat,
        scale: CGFloat
    ) -> KingfisherOptionsInfo {
        let scale = max(scale, 1)

        // PIXELS, and the width specifically. PageDownsampler works out the max
        // pixel size per image from its own aspect ratio, because bounding the
        // longest side - which is what DownsamplingImageProcessor does - starves
        // a tall strip of exactly the dimension it is drawn at
        let target = max(width, 1) * scale

        return [
            .backgroundDecode,
            .processor(PageDownsampler(width: target)),
            .scaleFactor(scale),
            .requestModifier(AnyModifier.headers(headers)),
            .cacheOriginalImage,
        ]
    }
}

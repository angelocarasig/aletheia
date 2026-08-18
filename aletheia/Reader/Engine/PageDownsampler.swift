//
//  PageDownsampler.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import ImageIO
import Kingfisher
import UIKit

// downsamples a page to the width it will be drawn at, rather than to its
// longest side.
//
// Kingfisher's DownsamplingImageProcessor hands ImageIO a single
// kCGImageSourceThumbnailMaxPixelSize, which bounds whichever side is longer.
// on a paged page that is the height and roughly the same as bounding the
// width, so it looks right. on a strip it is catastrophically not: an 800x1580
// slice asked to fit 1206px comes back 611px wide and is then drawn at 1206,
// upscaled twice over. taller slices are worse in proportion.
//
// so the max pixel size is derived per image from its own aspect ratio, read
// out of the header before any pixels are decoded. the identifier deliberately
// does NOT vary with it - it is keyed on the target width alone, so the cell and
// the prefetcher produce the same cache key for every page
struct PageDownsampler: ImageProcessor {
    let identifier: String

    private let width: CGFloat
    private let cap: CGFloat

    // a strip long enough to need more than this is past what a single texture
    // can hold anyway (Metal tops out at 16384), and the memory is not worth it.
    // such a page loses horizontal detail rather than failing - splitting is the
    // real answer and is not built. see features/page-dimensions.md
    private enum Limit {
        static let longSide: CGFloat = 8192
    }

    init(width: CGFloat, cap: CGFloat = Limit.longSide) {
        self.width = max(1, width.rounded())
        self.cap = cap
        self.identifier = "moe.aletheia.page-downsample(\(Int(self.width)),\(Int(cap)))"
    }

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo)
        -> KFCrossPlatformImage?
    {
        switch item {
        case .image(let image):
            // already decoded by someone else, and there is nothing to gain by
            // rasterising it a second time
            return image
        case .data(let data):
            return downsample(data, scale: options.scaleFactor)
        }
    }

    private func downsample(_ data: Data, scale: CGFloat) -> KFCrossPlatformImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            // honours EXIF orientation, so the dimensions read below and the
            // pixels produced describe the same picture
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(of: source),
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    // header-only read: properties never rasterise, so this costs a parse of the
    // first few hundred bytes. a file that will not state its size falls back to
    // the target width, which is the old behaviour and no worse
    private func maxPixelSize(of source: CGImageSource) -> CGFloat {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
            pixelWidth > 0, pixelHeight > 0
        else { return width }

        // bound the long side by whatever puts the SHORT side at the target
        // width. a landscape page is already bounded by its width, so it is
        // unchanged; a portrait one gets the height it actually needs
        let longSide = max(width, width * (pixelHeight / pixelWidth))
        return min(longSide, cap)
    }
}

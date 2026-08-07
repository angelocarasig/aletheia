//
//  PagePrefetcher.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import UIKit
import Kingfisher

// warms a band of pages either side of what is on screen. symmetric on purpose
// - scrolling back a page should be as instant as scrolling forward
@MainActor
final class PagePrefetcher {
    private var prefetcher: ImagePrefetcher?
    private var warmed: [URL] = []

    private let count: Int
    private let width: CGFloat
    // the cell and this must derive the same downsample size or they key into
    // different cache entries and every warmed page is wasted
    private let scale: CGFloat

    init(count: Int, width: CGFloat, scale: CGFloat) {
        self.count = max(0, count)
        self.width = width
        self.scale = scale
    }

    func update(visible: Range<Int>, in pages: [ReaderPage]) {
        guard count > 0, !pages.isEmpty else { return }

        let lower = max(0, visible.lowerBound - count)
        let upper = min(pages.count, visible.upperBound + count)
        guard lower < upper else { return }

        let band = pages[lower..<upper]
        let urls = band.map(\.url)
        guard urls != warmed else { return }

        warmed = urls
        prefetcher?.stop()

        // a page's headers are per-source, and one band can straddle a chapter
        // boundary, so the band is grouped rather than warmed with one set
        let resources = Dictionary(grouping: band, by: \.headers)
        let sources = resources.map { headers, pages in
            (headers: headers, urls: pages.map(\.url))
        }

        guard let first = sources.first else { return }

        // ImagePrefetcher takes one options set, so the common case (a band
        // inside a single chapter) prefetches directly and a straddling band
        // warms the dominant side - the rest arrives through the cells
        let prefetcher = ImagePrefetcher(
            urls: sources.count == 1 ? first.urls : urls,
            options: ReaderImage.options(headers: first.headers, width: width, scale: scale)
        )
        prefetcher.start()
        self.prefetcher = prefetcher
    }

    func stop() {
        prefetcher?.stop()
        prefetcher = nil
        warmed = []
    }
}

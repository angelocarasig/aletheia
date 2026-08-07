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

    init(count: Int, width: CGFloat) {
        self.count = max(0, count)
        self.width = width
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

        // a page's referer is per-source, and one band can straddle a chapter
        // boundary, so the band is grouped rather than warmed with one header
        let resources = Dictionary(grouping: band, by: \.referer)
        let sources = resources.map { referer, pages in
            (referer: referer, urls: pages.map(\.url))
        }

        guard let first = sources.first else { return }

        // ImagePrefetcher takes one options set, so the common case (a band
        // inside a single chapter) prefetches directly and a straddling band
        // warms the dominant side - the rest arrives through the cells
        let prefetcher = ImagePrefetcher(
            urls: sources.count == 1 ? first.urls : urls,
            options: ReaderImage.options(referer: first.referer, width: width)
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

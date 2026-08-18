//
//  ReaderConfiguration.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

struct ReaderConfiguration: Equatable, Sendable {
    var mode: Orientation = .leftToRight
    var dim: Double = 0
    var chromeTint: Double = Defaults.chromeTint
    var horizontalPadding: CGFloat = 0
    var grayscale: Bool = false
    var inverted: Bool = false
    // stored under the defaults key "reader.warmth" - renaming this property
    // silently resets it for every reader who already set one
    var warmth: Double = 0
    // not a render property; the controller ignores it. rides this struct
    // anyway since every other reader preference does
    var keepScreenOn: Bool = false
    var autoScrollSpeed: CGFloat = Defaults.autoScrollSpeed
    var autoAdvanceInterval: TimeInterval = Defaults.autoAdvanceInterval
    var prefetchCount: Int = Defaults.prefetchCount
    var windowSize: Int = Defaults.windowSize
    var preloadThreshold: CGFloat = Defaults.preloadThreshold

    enum Defaults {
        static let chromeTint: Double = 0.4
        static let maxChromeTint: Double = 0.7

        static let autoScrollSpeed: CGFloat = 300
        static let minAutoScrollSpeed: CGFloat = 260
        static let maxAutoScrollSpeed: CGFloat = 500

        static let maxHorizontalPadding: CGFloat = 48

        // signed: positive removes blue, negative removes red, zero tints
        // nothing - the bound applies to magnitude
        static let maxWarmth: Double = 0.7
        static let warmthStep: Double = 0.05
        static let warmthTone = (red: 1.0, green: 0.76, blue: 0.47)
        static let coolTone = (red: 0.47, green: 0.76, blue: 1.0)

        // a paged mode dwells then slides, so its auto-scroll setting is a
        // duration, not a rate - a different unit from autoScrollSpeed
        static let autoAdvanceInterval: TimeInterval = 5
        static let minAutoAdvanceInterval: TimeInterval = 1
        static let maxAutoAdvanceInterval: TimeInterval = 10
        static let prefetchCount = 3
        static let windowSize = 3
        static let preloadThreshold: CGFloat = 500
        static let maxDim: Double = 0.6

        // layout runs before the image lands, so the first pass uses this
        // ratio; corrected per page once it loads. height/width, not
        // width/height - a webtoon slice needs this direction, and one
        // constant for both would be wrong for the mode that needs it most
        static let pagedPageRatio: CGFloat = 1414.0 / 1000.0
        static let stripPageRatio: CGFloat = 1.435

        static let ratioSampleMinimum = 4
        static let ratioSampleCap = 12
    }
}

extension Orientation {
    // the engine never sees .unknown - the host resolves it first - but this
    // keeps every switch exhaustive without an unreachable default
    var resolved: Orientation {
        self == .unknown ? .leftToRight : self
    }

    // sanitised form tags are stored in: lowercased, spaces stripped
    static let stripTags: Set<String> = [
        "webtoon", "manhwa", "manhua", "longstrip", "webcomic",
    ]

    func resolved(tags: Set<String>) -> Orientation {
        guard self == .unknown else { return self }
        return tags.isDisjoint(with: Self.stripTags) ? .leftToRight : .infinite
    }

    var isVertical: Bool {
        resolved == .infinite || resolved == .vertical
    }

    var isHorizontal: Bool {
        !isVertical
    }

    var isContinuous: Bool {
        resolved == .infinite
    }

    var isPaged: Bool {
        !isContinuous
    }

    var isRightToLeft: Bool {
        resolved == .rightToLeft
    }

    var fallbackPageRatio: CGFloat {
        isContinuous
            ? ReaderConfiguration.Defaults.stripPageRatio
            : ReaderConfiguration.Defaults.pagedPageRatio
    }

    var label: String {
        switch resolved {
        case .infinite: "Infinite Scroll"
        case .vertical: "Vertical"
        case .leftToRight: "Left to Right"
        case .rightToLeft: "Right to Left"
        case .unknown: "Left to Right"
        }
    }

    var summary: String {
        switch resolved {
        case .infinite: "Continuous strip, best for webtoons"
        case .vertical: "One page at a time, top to bottom"
        case .leftToRight: "One page at a time, western order"
        case .rightToLeft: "One page at a time, manga order"
        case .unknown: "One page at a time, western order"
        }
    }
}

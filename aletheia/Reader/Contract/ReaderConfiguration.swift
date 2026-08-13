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
    // -maxWarmth...maxWarmth. the name stays singular because the stored key is
    // "reader.warmth" and renaming a defaults key silently resets it for every
    // reader who already set one
    var warmth: Double = 0
    // not a render property, and here anyway: every other reader preference
    // rides this struct from ReaderSettings to the view, and a second path for
    // one bool would be the only one of its kind. the controller ignores it
    var keepScreenOn: Bool = false
    var autoScrollSpeed: CGFloat = Defaults.autoScrollSpeed
    var autoAdvanceInterval: TimeInterval = Defaults.autoAdvanceInterval
    var prefetchCount: Int = Defaults.prefetchCount
    var windowSize: Int = Defaults.windowSize
    var preloadThreshold: CGFloat = Defaults.preloadThreshold
    
    enum Defaults {
        // clear glass is permanently transparent by design, so chrome over a
        // busy page has nothing to separate it from the art. a tint on the glass
        // is what Apple prescribes instead of a second scrim view
        static let chromeTint: Double = 0.4
        static let maxChromeTint: Double = 0.7
        
        static let autoScrollSpeed: CGFloat = 300
        static let minAutoScrollSpeed: CGFloat = 260
        static let maxAutoScrollSpeed: CGFloat = 500

        static let maxHorizontalPadding: CGFloat = 48

        // warmth is signed: positive takes the blue out, negative takes the red
        // out, zero tints nothing. the magnitude is what the bound applies to,
        // and full strength has to leave the art readable rather than coloured
        static let maxWarmth: Double = 0.7
        static let warmthStep: Double = 0.05
        static let warmthTone = (red: 1.0, green: 0.76, blue: 0.47)
        // the warm tone with its red and blue swapped, so the two ends pull the
        // page by the same amount in opposite directions
        static let coolTone = (red: 0.47, green: 0.76, blue: 1.0)
        
        // a paged mode dwells on a page and then slides, so its auto-scroll
        // setting is a duration rather than a rate. different unit, different
        // stored value - one number cannot mean both
        static let autoAdvanceInterval: TimeInterval = 5
        static let minAutoAdvanceInterval: TimeInterval = 1
        static let maxAutoAdvanceInterval: TimeInterval = 10
        static let prefetchCount = 3
        static let windowSize = 3
        static let preloadThreshold: CGFloat = 500
        static let maxDim: Double = 0.6
        
        // pages are laid out before their image lands, so the first pass uses a
        // ratio rather than a measurement. corrected per page on load.
        //
        // height/width, not width/height - a webtoon slice is far taller than
        // an ISO page and one constant for both is wrong for the mode that
        // needs it most
        static let pagedPageRatio: CGFloat = 1414.0 / 1000.0
        static let stripPageRatio: CGFloat = 1.435
        
        // how many real measurements a chapter needs before its own median
        // replaces the static guess, and where sampling stops paying for itself
        static let ratioSampleMinimum = 4
        static let ratioSampleCap = 12
    }
}

extension Orientation {
    // the engine is never handed .unknown - the host resolves it first - but
    // treating it as a definite mode keeps every switch exhaustive without an
    // unreachable default
    var resolved: Orientation {
        self == .unknown ? .leftToRight : self
    }
    
    // tags that mark a vertical-strip title (webtoon/manhwa/manhua), in the
    // sanitised form tags are stored in: lowercased, spaces stripped
    static let stripTags: Set<String> = [
        "webtoon", "manhwa", "manhua", "longstrip", "webcomic"
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
    
    // continuous scroll, one long strip. everything else snaps page to page
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

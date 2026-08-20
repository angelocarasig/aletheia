//
//  RegisterAxis.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// boys love and girls love read as a different register rather than a nearby
// genre, and crossing that line is a worse error than an ordinary bad
// recommendation. a seed only ever returns rows of its own class - the model
// enforces it as a hard filter and the class is precomputed in the flags byte
//
// not called Orientation: that name already means reading direction in this app,
// and the two have nothing to do with each other
enum RegisterAxis: Int, Sendable, Codable, CaseIterable {
    case general = 0
    case boysLove = 1
    case girlsLove = 2
}

// the model's own format vocabulary. it has no equivalent on a SeriesRecord -
// nothing in this app stores a format - so it exists here rather than in
// Models/Enums, which is for things the database knows about
enum CatalogFormat: Int, Sendable, Codable, CaseIterable {
    case manga = 0
    case manhwa = 1
    case manhua = 2
    case oel = 3
    case novel = 4
    case other = 5

    // the four the fixtures rank against, and the default for a reader browsing
    // comics. a novel recommended beside a comic is the classic misfire
    static let comics: Set<CatalogFormat> = [.manga, .manhwa, .manhua, .oel]
}

// wire values never reach a view. the model speaks a four-rung ladder and this
// app collapses the top two into Explicit, so mapping down loses a distinction
// and mapping up has to pick - pornographic, the most permissive rung, because
// anything lower would silently drop erotica from an Explicit reader's results
enum ContentCeiling: Int, Sendable {
    case safe = 0
    case suggestive = 1
    case erotica = 2
    case pornographic = 3

    init(_ classification: Classification) {
        switch classification {
        case .Safe: self = .safe
        case .Suggestive: self = .suggestive
        case .Explicit: self = .pornographic
        case .Unknown: self = .safe
        }
    }

    var classification: Classification {
        switch self {
        case .safe: .Safe
        case .suggestive: .Suggestive
        case .erotica, .pornographic: .Explicit
        }
    }
}

// the six states the metadata pack stores, in the order metadata.json lists them.
// tracker-mangabaka.md already settled these mappings, upcoming to Unknown
// included - a row claiming Ongoing when nothing has been published would be
// asserting chapters exist
enum CatalogStatus: Int, Sendable {
    case unknown = 0
    case releasing = 1
    case completed = 2
    case hiatus = 3
    case cancelled = 4
    case upcoming = 5

    var publication: Publication {
        switch self {
        case .releasing: .Ongoing
        case .completed: .Completed
        case .hiatus: .Hiatus
        case .cancelled: .Cancelled
        case .unknown, .upcoming: .Unknown
        }
    }
}

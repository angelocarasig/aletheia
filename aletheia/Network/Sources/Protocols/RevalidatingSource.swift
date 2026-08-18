//
//  RevalidatingSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// `stored` is a count of OUR rows, and only matches the server's total while
// nothing has been dropped in parsing or deleted upstream. either one makes them
// diverge permanently, after which this answers .changed forever and costs
// nothing but the comparison
protocol RevalidatingSource: SourceService {
    func chapters(seriesSlug: String, stored: Int) async throws -> ChapterRevalidation
}

enum ChapterRevalidation: Sendable {
    case unchanged
    /// empty means the series genuinely has none
    case changed([ChapterEntry])

    var summary: String {
        switch self {
        case .unchanged: "reported no change"
        case .changed(let entries): "fetched \(entries.count) chapter(s)"
        }
    }
}

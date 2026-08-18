//
//  RevalidatingSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// an opt-in for the rare source whose server states its own chapter total, so it
// can answer "nothing changed" from the first response instead of walking a
// paginated feed to the end. everyone else conforms to SourceService alone and
// simply fetches - the base contract stays one method returning one list.
//
// worth knowing before conforming: `stored` is a count of OUR rows, and it only
// matches the server's total while nothing has been dropped in parsing and
// nothing has been deleted upstream. either one makes them diverge permanently,
// after which this answers .changed forever and costs nothing but the comparison
protocol RevalidatingSource: SourceService {
    func chapters(seriesSlug: String, stored: Int) async throws -> ChapterRevalidation
}

enum ChapterRevalidation: Sendable {
    /// the stored list still stands, so nothing is fetched or written
    case unchanged
    /// the list as it is now. empty means the series genuinely has none
    case changed([ChapterEntry])

    var summary: String {
        switch self {
        case .unchanged: "reported no change"
        case .changed(let entries): "fetched \(entries.count) chapter(s)"
        }
    }
}

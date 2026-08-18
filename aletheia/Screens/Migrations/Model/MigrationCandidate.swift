//
//  MigrationCandidate.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// what a source search turned up for one migration entry. carries only what
// SeriesStub actually has - year and chapter count are detail-level facts no
// search result exposes, so this does not pretend to have them
struct MigrationCandidate: Identifiable, Sendable, Hashable {
    let sourceSlug: String
    let stub: SeriesStub

    var id: String { "\(sourceSlug):\(stub.slug)" }
    var title: String { stub.title }
    var cover: URL? { stub.cover }
}

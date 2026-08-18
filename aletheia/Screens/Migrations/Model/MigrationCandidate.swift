//
//  MigrationCandidate.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

struct MigrationCandidate: Identifiable, Sendable, Hashable {
    let sourceSlug: String
    let stub: SeriesStub

    var id: String { "\(sourceSlug):\(stub.slug)" }
    var title: String { stub.title }
    var cover: URL? { stub.cover }
}

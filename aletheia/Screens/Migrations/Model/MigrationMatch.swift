//
//  MigrationMatch.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// found always carries every candidate, even when one is pre-selected, so
// the reader can still override without re-searching
enum MigrationMatch: Equatable, Sendable {
    case idle
    case searching
    case found([MigrationCandidate], selected: MigrationCandidate?)
    case notFound
    case failed(String)

    var candidates: [MigrationCandidate] {
        if case .found(let candidates, _) = self { candidates } else { [] }
    }

    var selected: MigrationCandidate? {
        if case .found(_, let selected) = self { selected } else { nil }
    }
}

//
//  TrackerRestoreMatch.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// one row's search outcome. `found` always carries every candidate search
// turned up, even when one is pre-selected - the reader can still override a
// confident guess without re-searching
enum TrackerRestoreMatch: Equatable, Sendable {
    case idle
    case searching
    case found([TrackerRestoreCandidate], selected: TrackerRestoreCandidate?)
    case notFound
    case failed(String)

    var candidates: [TrackerRestoreCandidate] {
        if case let .found(candidates, _) = self { candidates } else { [] }
    }

    var selected: TrackerRestoreCandidate? {
        if case let .found(_, selected) = self { selected } else { nil }
    }
}

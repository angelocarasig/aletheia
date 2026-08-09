//
//  LoadPhase.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

// the one value a loading surface branches on AND animates on - the same value,
// always, because every dead or partial swap traced to those two diverging. a
// surface derives it from its own state and may never reach every case.
// see docs/features/loading-transitions.md
enum LoadPhase: Equatable {
    case pending
    case empty
    case content
    case failed
}

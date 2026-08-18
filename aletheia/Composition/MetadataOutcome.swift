//
//  MetadataOutcome.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// shared by OriginRefresher (source side) and TrackerSyncer (tracker side), so
// a details-screen row and a library-wide walk both read one vocabulary
enum MetadataOutcome: Equatable, Sendable {
    case updated
    case unchanged
    case failed(String)
    // same distinction OriginRefresher.Outcome draws for chapters - never
    // recorded or shown as a failure
    case cancelled
}

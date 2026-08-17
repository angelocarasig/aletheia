//
//  MetadataOutcome.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// what a single supplier - a source origin or a linked tracker - answered
// when asked to refresh its half of a series' metadata. shared by
// OriginRefresher (source side) and TrackerSyncer (tracker side), so a
// details-screen row and a library-wide walk both read one vocabulary
enum MetadataOutcome: Equatable, Sendable {
    case updated
    case unchanged
    case failed(String)
    // the run was stopped, same distinction OriginRefresher.Outcome already
    // draws for chapters - never recorded as a failure, never shown as one
    case cancelled
}

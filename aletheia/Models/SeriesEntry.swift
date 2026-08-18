//
//  SeriesEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation

// what a screen resolves matching to is view model state, never stored here
enum SeriesEntry: Sendable, Hashable {
    case source(sourceSlug: String, stub: SeriesStub)
    case library(SeriesRecord.ID)
}

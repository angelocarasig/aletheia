//
//  SeriesEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation

// where a details screen was opened from. the case carries exactly what that
// route can supply, so there is no combination of fields to validate: a sourced
// entry always has a provider to fetch from, a library entry always has a row to
// read. what matching later resolves to is view model state, never stored here
enum SeriesEntry: Sendable, Hashable {
    case source(sourceSlug: String, stub: SeriesStub)
    case library(SeriesRecord.ID)
}

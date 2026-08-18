//
//  MigrationEntry.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import Tagged

// one row of whatever a migration pulls from - a tracker's list, a parsed
// backup file, or a query over series already in this library. never
// persisted itself - this is session-only working data, gone the moment the
// screen closes unless it was Saved
//
// existingSeriesId is the fork every commit chain has to make: nil means the
// entry describes something outside the library and Save may have to mint a
// new series (tracker restore, file import). a real id means the series is
// already known - Save only ever attaches a new origin to it, never creates
// (source migration, disconnected-source migration)
protocol MigrationEntry: Identifiable, Sendable, Hashable {
    var title: String { get }
    var cover: URL? { get }
    var existingSeriesId: SeriesRecord.ID? { get }
}

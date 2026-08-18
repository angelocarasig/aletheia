//
//  MigrationRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// saving/outcome are kept separate from match so a row can be re-searched
// after a failed save without losing what was found
struct MigrationRow<Entry: MigrationEntry>: Identifiable, Sendable {
    let entry: Entry
    var precheckMatched = false
    var match: MigrationMatch = .idle
    var saving = false
    var outcome: MigrationOutcome?

    var id: Entry.ID { entry.id }

    var canSave: Bool {
        !precheckMatched && match.selected != nil && !saving && outcome == nil
    }

    var canSkip: Bool {
        guard !precheckMatched else { return false }

        switch outcome {
        case .failed, .cancelled: return true
        case .saved, .skipped: return false
        case nil: break
        }

        switch match {
        case .notFound, .failed: return true
        case .idle, .searching, .found: return false
        }
    }

    var isSettled: Bool {
        switch outcome {
        case .saved, .skipped: true
        case .failed, .cancelled, nil: false
        }
    }
}

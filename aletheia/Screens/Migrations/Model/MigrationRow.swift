//
//  MigrationRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// one queue row: the entry's own facts plus everything this screen has
// learned about it since. `saving`/`outcome` are separate from `match`
// because a row can be re-searched after a failed save without losing what
// was found
struct MigrationRow<Entry: MigrationEntry>: Identifiable, Sendable {
    let entry: Entry
    // set once, when the row is built: an upfront precheck already found a
    // local match for this entry before search ever ran - a tracker restore
    // row already linked by a previous session, a source-migration row
    // already carrying the target source. never searched, selected, or
    // saved - it exists to be seen in its own pill, not acted on again
    var precheckMatched = false
    var match: MigrationMatch = .idle
    var saving = false
    var outcome: MigrationOutcome?

    var id: Entry.ID { entry.id }

    // Save is the first attempt only - once it has failed once, the slot
    // where it lived becomes Skip instead (canSkip), not a repeated Save
    var canSave: Bool {
        !precheckMatched && match.selected != nil && !saving && outcome == nil
    }

    // a row is skippable whenever it has hit a dead end it can't recover
    // from on its own - a failed/cancelled save, but also a search that
    // came back with nothing or that failed outright. saved/skipped rows
    // have already left the working set and offer nothing further
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

    // saved and skipped are the two outcomes that leave the working set -
    // everything else (nil, failed, cancelled) still needs the reader's
    // attention and stays in it
    var isSettled: Bool {
        switch outcome {
        case .saved, .skipped: true
        case .failed, .cancelled, nil: false
        }
    }
}

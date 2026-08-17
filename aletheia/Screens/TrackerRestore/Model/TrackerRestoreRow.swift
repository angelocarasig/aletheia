//
//  TrackerRestoreRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// one queue row: the tracker's own facts plus everything this screen has
// learned about it since. `saving`/`outcome` are separate from `match`
// because a row can be re-searched after a failed save without losing what
// was found
struct TrackerRestoreRow: Identifiable, Sendable {
    let entry: TrackerImportEntry
    // set once, when the row is built: this exact tracker + remoteId was
    // already linked to a local series before this pull ran - by a previous
    // restore, or by hand from Details. never searched, selected, or saved -
    // it exists to be seen in its own pill, not acted on again
    var alreadyLinked = false
    var match: TrackerRestoreMatch = .idle
    var saving = false
    var outcome: TrackerRestoreOutcome?

    var id: Int64 { entry.id }

    // Save is the first attempt only - once it has failed once, the slot
    // where it lived becomes Skip instead (canSkip), not a repeated Save
    var canSave: Bool {
        !alreadyLinked && match.selected != nil && !saving && outcome == nil
    }

    // a row is skippable whenever it has hit a dead end it can't recover
    // from on its own - a failed/cancelled save, but also a search that
    // came back with nothing or that failed outright. saved/skipped rows
    // have already left the working set and offer nothing further
    var canSkip: Bool {
        guard !alreadyLinked else { return false }

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

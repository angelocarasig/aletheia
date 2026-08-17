//
//  TrackerRestoreOutcome.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import Foundation

// what Save produced, mirroring MetadataOutcome's shape - a row that
// finished says how, not just that it did.
//
// `failed`/`cancelled` do not move a row out of the working set on their
// own - the reader sees the reason and a Skip button, and skipped is the
// only outcome, besides saved, that actually leaves a row behind. this is
// deliberate: a save failure is very often transient (a token expired, a
// source hiccuped), and moving the row away before the reader has seen why
// would bury it
enum TrackerRestoreOutcome: Equatable, Sendable {
    case saved
    case failed(String)
    case skipped(String)
    case cancelled

    var reason: String? {
        switch self {
        case .failed(let reason), .skipped(let reason): reason
        case .saved, .cancelled: nil
        }
    }
}

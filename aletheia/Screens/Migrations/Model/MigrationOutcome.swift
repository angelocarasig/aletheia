//
//  MigrationOutcome.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// failed/cancelled do not leave the working set on their own - only skipped
// and saved do. deliberate: a save failure is often transient (expired
// token, source hiccup), so the row stays visible until the reader skips it
enum MigrationOutcome: Equatable, Sendable {
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

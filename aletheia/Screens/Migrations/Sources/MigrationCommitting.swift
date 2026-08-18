//
//  MigrationCommitting.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// the real Save chain for one row - whatever it takes to turn a picked
// candidate into a real library entry. every concrete implementation shares
// the same shape (create-or-attach, fetch chapters, apply progress) but
// differs in how progress is sourced and what runs after - a tracker link,
// an old origin's removal, or nothing at all. that difference is why this
// is one method per implementation rather than a single shared function with
// branches: each flow's own file is where its trailing effect belongs
protocol MigrationCommitting<Entry>: Sendable {
    associatedtype Entry: MigrationEntry
    func commit(_ entry: Entry, candidate: MigrationCandidate) async -> MigrationOutcome
}

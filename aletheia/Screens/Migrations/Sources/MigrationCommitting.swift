//
//  MigrationCommitting.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

protocol MigrationCommitting<Entry>: Sendable {
    associatedtype Entry: MigrationEntry
    func commit(_ entry: Entry, candidate: MigrationCandidate) async -> MigrationOutcome
}

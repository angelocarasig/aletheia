//
//  MigrationSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// wherever a migration's whole entry list comes from, pulled once - a
// tracker's list (LiveTrackerImportSource), a parsed backup file, or a
// query over series already in this library (source/disconnected
// migration). generic over the entry type it produces, so the composer that
// drives the queue never needs to know which
protocol MigrationSource<Entry>: Sendable {
    associatedtype Entry: MigrationEntry
    func fetch() async throws -> [Entry]
}

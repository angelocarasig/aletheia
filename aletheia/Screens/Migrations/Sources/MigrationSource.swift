//
//  MigrationSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

protocol MigrationSource<Entry>: Sendable {
    associatedtype Entry: MigrationEntry
    func fetch() async throws -> [Entry]
}

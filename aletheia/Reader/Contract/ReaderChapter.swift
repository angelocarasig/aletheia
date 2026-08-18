//
//  ReaderChapter.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// position in the array supplied to the engine IS reading order - the engine
// never sorts by number
struct ReaderChapter: Identifiable, Hashable, Sendable {
    typealias ID = Int64

    let id: ID
    let number: Double
    let title: String

    init(id: ID, number: Double, title: String) {
        self.id = id
        self.number = number
        self.title = title
    }
}

//
//  SearchPage.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

struct SearchPage<Item: Sendable>: Sendable {
    let items: [Item]
    let next: Int?
}

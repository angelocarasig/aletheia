//
//  SearchPage.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

/// a page of results plus the next page number (nil == last page).
struct SearchPage<Item: Sendable>: Sendable {
    let items: [Item]
    let next: Int?
}

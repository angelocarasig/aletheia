//
//  SearchVisibility.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

// unset is not "shown" - it is "no opinion yet": an adult source defaults to
// hidden from search, but an explicit choice always overrides that default
// in either direction
enum SearchVisibility: String, Codable, Sendable, CaseIterable {
    case unset
    case hidden
    case shown

    func hides(adultSource: Bool) -> Bool {
        switch self {
        case .hidden: true
        case .shown: false
        case .unset: adultSource
        }
    }
}

//
//  Classification.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

enum Classification: String, Codable, Sendable, CaseIterable {
    case Unknown
    case Safe
    case Suggestive
    case Explicit
}

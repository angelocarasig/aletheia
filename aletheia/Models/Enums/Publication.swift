//
//  Publication.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

enum Publication: String, Codable, Sendable, CaseIterable {
    case Unknown
    case Ongoing
    case Completed
    case Hiatus
    case Cancelled
}

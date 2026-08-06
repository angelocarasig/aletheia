//
//  Status.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

/// a user's reading status for a series
enum Status: String, Codable, Sendable, CaseIterable {
    case reading
    case completed
    case paused
    case dropped
    case planning
}

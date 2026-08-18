//
//  ScoreFormat.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// the stored value is always canonical 0...100 raw; the format only decides
// how it's drawn, which is what makes switching scale a display change
// rather than a data migration. raw values are anilist's wire strings so a
// viewer decodes straight into this
enum ScoreFormat: String, Codable, Sendable, CaseIterable {
    case point100 = "POINT_100"
    case point10Decimal = "POINT_10_DECIMAL"
    case point10 = "POINT_10"
    case point5 = "POINT_5"
    case point3 = "POINT_3"

    // 0 is unscored on both services - a value, not an absence - so clearing
    // a score writes 0 rather than omitting the field
    var steps: [Int] {
        switch self {
        case .point100: Array(0...100)
        case .point10Decimal: stride(from: 0, through: 100, by: 5).map { $0 }
        case .point10: stride(from: 0, through: 100, by: 10).map { $0 }
        case .point5: stride(from: 0, through: 100, by: 20).map { $0 }
        // the three smiley faces, spaced across the range they answer for
        case .point3: [0, 35, 60, 85]
        }
    }

    func label(for raw: Int) -> String {
        guard raw > 0 else { return "No Score" }

        return switch self {
        case .point100: "\(raw)"
        case .point10Decimal: String(format: "%.1f", Double(raw) / 10)
        case .point10: "\(Int((Double(raw) / 10).rounded()))"
        case .point5: "\(Int((Double(raw) / 20).rounded()))"
        case .point3: raw >= 85 ? "Loved" : raw >= 60 ? "Liked" : "Disliked"
        }
    }

    // myanimelist takes a fixed 0...10 integer on the wire, which is the same
    // conversion .point10 renders with
    static func mal(from raw: Int) -> Int {
        min(10, max(0, Int((Double(raw) / 10).rounded())))
    }

    static func raw(fromMal score: Int) -> Int {
        min(100, max(0, score * 10))
    }
}

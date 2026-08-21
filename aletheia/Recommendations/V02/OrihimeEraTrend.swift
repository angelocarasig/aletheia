//
//  OrihimeEraTrend.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// params/era-tag-trend.json: lowercased tag name -> how wave-bound that tag
// is (0 = spread evenly across years, 1 = bunched into a six-year window).
// only tags above the training-side threshold are present at all - a name
// missing here trends at 0, exactly era.py's tag_trend_of.get(name, 0.0)
struct OrihimeEraTrend: Sendable {
    private let trendOf: [String: Double]

    init(bundle: OrihimeBundle) throws {
        let data = try bundle.blob("params/era-tag-trend.json")
        do {
            trendOf = try JSONDecoder().decode([String: Double].self, from: data)
        } catch {
            throw RecommenderError.malformed(
                file: "era-tag-trend.json", reason: String(describing: error))
        }
    }

    // mean of the seed's top `topCount` most wave-bound tags - era.py's
    // similarity_to_virtual(): sorted(trends, reverse=True)[:top], averaged
    // over `top` even when fewer than `top` tags matched at all
    func trend(forTagNames names: [String], top topCount: Int) -> Double {
        guard topCount > 0 else { return 0 }
        let trends = names.map { trendOf[$0.lowercased()] ?? 0 }.sorted(by: >)
        let head = trends.prefix(topCount)
        guard !head.isEmpty else { return 0 }
        return head.reduce(0, +) / Double(topCount)
    }
}

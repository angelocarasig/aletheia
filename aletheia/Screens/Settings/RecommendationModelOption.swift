//
//  RecommendationModelOption.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026
//

import Foundation

// one entry per RecommenderService this app actually ships an adapter for -
// not a mirror of whatever a manifest happens to list. a pack the app can't
// read is not a pickable option, so the list is fixed here rather than
// pulled live from AssetPackManager.shared.allAssetPacks
struct RecommendationModelOption: Identifiable, Sendable {
    let packId: String
    let name: String
    let subtitle: String

    var id: String { packId }

    static let all: [RecommendationModelOption] = [
        RecommendationModelOption(
            packId: "protostar-1-0-0",
            name: "Protostar",
            subtitle: "The current recommendation model"
        )
    ]
}

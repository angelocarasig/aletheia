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
    // the fileSelectors directory ba-package bakes into the .aar - preserved
    // as a literal subfolder inside the pack, not flattened, so every file
    // read against this pack is rooted here
    let assetRoot: String

    var id: String { packId }

    static let all: [RecommendationModelOption] = [
        RecommendationModelOption(
            packId: "protostar-1-0-0",
            name: "Protostar",
            subtitle: "The current recommendation model",
            assetRoot: "protostar-1-0-0-2026.08"
        ),
        // temporary exception to the rule above - no OrihimeRecommender exists yet
        // (v02 phase 2b). here early only so Download/Remove give dev-side control
        // over the pack while iterating on pack rebuilds; selecting it as active
        // degrades gracefully to no results, same as any other unavailable model
        RecommendationModelOption(
            packId: "orihime-2-0-0",
            name: "Orihime",
            subtitle: "Not wired to a recommender yet - for pack testing only",
            assetRoot: "orihime-2-0-0-2026.08"
        ),
    ]
}

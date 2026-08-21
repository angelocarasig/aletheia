//
//  RecommendationModelOption.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026
//

import Foundation

// which concrete RecommenderService a pack's files load through - the join
// RecommendationsService needs to build the right adapter for whichever
// packId the reader picks, since two packs never share one loader
enum RecommendationAdapter: Sendable {
    case v01
    case orihime
}

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
    let adapter: RecommendationAdapter

    var id: String { packId }

    static let all: [RecommendationModelOption] = [
        RecommendationModelOption(
            packId: "protostar-1-0-0",
            name: "Protostar",
            subtitle: "The current recommendation model",
            assetRoot: "protostar-1-0-0-2026.08",
            adapter: .v01
        ),
        RecommendationModelOption(
            packId: "orihime-2-0-0",
            name: "Orihime",
            subtitle: "A richer blend - resolved titles only for now",
            assetRoot: "orihime-2-0-0-2026.08",
            adapter: .orihime
        ),
    ]
}

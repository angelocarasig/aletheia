//
//  BackgroundDownloadHandler.swift
//  RecommendationModels
//
//  Created by Angelo Carasig on 20/8/2026.
//

import BackgroundAssets
import ExtensionFoundation

@main
struct DownloaderExtension: ManagedDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        return true
    }
}

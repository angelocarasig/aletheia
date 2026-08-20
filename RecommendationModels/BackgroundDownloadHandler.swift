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
        // Use this method to filter out asset packs that the system would otherwise download automatically. You can also remove this method entirely if you just want to rely on the default download behavior.
        return true
    }
}

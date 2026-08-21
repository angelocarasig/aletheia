//
//  RecommendationsService.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026
//

import Foundation

// selectedPackId and loadedPackId are deliberately two ids, not one:
// selectedPackId is the reader's persisted choice, loadedPackId is whichever
// pack this process actually built a scorer for at launch, never changed
// mid-session - a live swap would page in a new 116 MB model on whatever
// screen happens to be open when the reader taps, and iOS has no clean way
// to page one back out again
actor RecommendationsService: RecommenderService {
    private var current: Recommender?
    private(set) var loadedPackId: String?
    private(set) var selectedPackId: String?

    private var continuation: AsyncStream<Bool>.Continuation?

    init(options: [RecommendationModelOption]) {
        guard let selected = UserDefaults.standard.string(forKey: Preferences.Key.recommenderPackId)
        else { return }
        selectedPackId = selected
        guard let option = options.first(where: { $0.packId == selected }) else { return }
        loadedPackId = option.packId
        current = Self.build(option)
    }

    private static func build(_ option: RecommendationModelOption) -> Recommender {
        switch option.adapter {
        case .v01:
            return V01Recommender(source: .assetPack(id: option.packId, root: option.assetRoot))
        case .orihime:
            return OrihimeRecommender(
                source: .assetPack(id: option.packId, root: option.assetRoot))
        }
    }

    var descriptor: RecommenderDescriptor {
        get async {
            await current?.descriptor
                ?? RecommenderDescriptor(
                    slug: "none", name: "No Model",
                    formatVersion: 0, titleCount: 0,
                    encodesText: false, hasMetadata: false)
        }
    }

    func warm() async {
        await current?.warm()
    }

    func recommend(
        _ payload: Payload,
        ceiling: ContentCeiling,
        formats: Set<CatalogFormat>,
        limit: Int
    ) async throws -> RecommendationSet {
        guard let current else { throw RecommenderError.unavailable }
        return try await current.recommend(
            payload, ceiling: ceiling, formats: formats, limit: limit)
    }

    func select(_ option: RecommendationModelOption) {
        guard selectedPackId != option.packId else { return }
        selectedPackId = option.packId
        UserDefaults.standard.set(option.packId, forKey: Preferences.Key.recommenderPackId)
        continuation?.yield(pendingRestart)
    }

    // the pack being removed no longer exists on disk once this returns - a
    // persisted selection pointing at it would otherwise survive into the
    // next launch and fail there instead of here
    func deselect(_ packId: String) {
        guard selectedPackId == packId else { return }
        selectedPackId = nil
        UserDefaults.standard.removeObject(forKey: Preferences.Key.recommenderPackId)
        continuation?.yield(pendingRestart)
    }

    private var pendingRestart: Bool {
        selectedPackId != nil && selectedPackId != loadedPackId
    }

    // select() can happen on any screen; only the root of the app consumes
    // this to show the restart prompt
    var pendingRestartUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(pendingRestart)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    private func clearContinuation() {
        continuation = nil
    }
}

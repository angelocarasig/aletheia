//
//  RecommendationsViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026
//

import BackgroundAssets
import Foundation
import Observation

@MainActor
@Observable
final class RecommendationsViewModel {
    struct ModelState {
        var status: AssetPack.Status = []
        // nil means "not currently downloading" - distinct from 0, which is a
        // real in-progress fraction
        var progress: Double?
        var errorMessage: String?
    }

    private(set) var states: [String: ModelState] = [:]
    // the reader's choice - not necessarily what this process is actually
    // scoring with yet
    private(set) var selectedPackId: String?

    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var service: RecommendationsService?

    func configure(service: RecommendationsService) {
        self.service = service
        guard selectedPackId == nil else { return }
        Task { selectedPackId = await service.selectedPackId }
    }

    func isDownloaded(_ option: RecommendationModelOption) -> Bool {
        states[option.packId]?.status.contains(.downloaded) ?? false
    }

    func isActive(_ option: RecommendationModelOption) -> Bool {
        option.packId == selectedPackId
    }

    func isDownloading(_ option: RecommendationModelOption) -> Bool {
        states[option.packId]?.progress != nil
    }

    // one watcher per pack, started once and left running for the screen's
    // lifetime - status can change from outside this screen (a background
    // download finishing while Settings isn't open), so this isn't a one-shot
    // fetch
    func watch(_ option: RecommendationModelOption) {
        guard watchers[option.packId] == nil else { return }

        watchers[option.packId] = Task { [weak self] in
            guard let self else { return }

            do {
                let status = try await AssetPackManager.shared.status(
                    ofAssetPackWithID: option.packId)
                self.states[option.packId, default: ModelState()].status = status
            } catch {
                self.states[option.packId, default: ModelState()].errorMessage =
                    error.localizedDescription
            }

            for await update in AssetPackManager.shared.statusUpdates(
                forAssetPackWithID: option.packId)
            {
                guard !Task.isCancelled else { return }
                self.apply(update, to: option.packId)
            }
        }
    }

    private func apply(_ update: AssetPackManager.DownloadStatusUpdate, to packId: String) {
        switch update {
        case .began:
            states[packId, default: ModelState()].progress = 0
            states[packId, default: ModelState()].errorMessage = nil
        case .paused:
            break
        case .downloading(_, let progress):
            states[packId, default: ModelState()].progress = progress.fractionCompleted
        case .finished:
            states[packId, default: ModelState()].progress = nil
            states[packId, default: ModelState()].status = .downloaded
        case .failed(_, let error):
            states[packId, default: ModelState()].progress = nil
            states[packId, default: ModelState()].errorMessage = error.localizedDescription
        @unknown default:
            break
        }
    }

    func download(_ option: RecommendationModelOption) {
        Task {
            do {
                let pack = try await AssetPackManager.shared.assetPack(withID: option.packId)
                try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
                states[option.packId, default: ModelState()].status = .downloaded
                await activate(option)
            } catch {
                states[option.packId, default: ModelState()].errorMessage =
                    error.localizedDescription
            }
        }
    }

    func select(_ option: RecommendationModelOption) {
        Task { await activate(option) }
    }

    func remove(_ option: RecommendationModelOption) {
        Task {
            do {
                try await AssetPackManager.shared.remove(assetPackWithID: option.packId)
                states[option.packId, default: ModelState()].status = []
                states[option.packId, default: ModelState()].errorMessage = nil
                await service?.deselect(option.packId)
                if selectedPackId == option.packId { selectedPackId = nil }
            } catch {
                states[option.packId, default: ModelState()].errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func activate(_ option: RecommendationModelOption) async {
        guard let service else { return }
        await service.select(option)
        selectedPackId = option.packId
    }
}

//
//  SourcePresetViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Observation

@MainActor
@Observable
final class SourcePresetViewModel {
    enum Phase {
        case loading
        case loaded([SeriesStub])
        case failed(Failure)
    }

    private let source: Source
    private let preset: SourcePreset
    private let correlator: Correlator

    private(set) var phase: Phase = .loading

    var isIdle: Bool {
        if case .loading = phase { return true }
        return false
    }

    init(source: Source, preset: SourcePreset, database: DatabaseClient) {
        self.source = source
        self.preset = preset
        self.correlator = Correlator(sourceSlug: source.descriptor.slug, database: database)
    }

    func match(for stub: SeriesStub) -> SeriesMatch? {
        correlator[stub]
    }

    func stop() {
        correlator.stop()
    }

    func resume() {
        guard case .loaded(let items) = phase else { return }
        correlator.observe(items)
    }

    #if DEBUG
        // phase is private(set) - an extension in the preview file could not set it
        func preview(phase: Phase) {
            self.phase = phase
        }
    #endif

    func load() async {
        phase = .loading
        do {
            let page = try await source.search(preset.query())
            phase = .loaded(page.items)
            resume()
        } catch {
            // cancellation arrives as either type - URLSession maps its own
            // cancellation onto NetworkError too
            let cancelled =
                error is CancellationError || (error as? NetworkError)?.isCancellation == true
            if !cancelled {
                AppLog.shared.log(
                    "preset '\(preset.id)' load failed - \(error)", level: .error,
                    category: "sources")
            }
            phase = .failed(Failure(error, fallback: "Couldn't Load"))
        }
    }
}

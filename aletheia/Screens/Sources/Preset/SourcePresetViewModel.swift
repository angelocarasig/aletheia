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
        case failed
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

    // the row stops observing when it scrolls away or is navigated past, so
    // coming back has to pick the observation up again from what is already loaded
    func resume() {
        guard case .loaded(let items) = phase else { return }
        correlator.observe(items)
    }

    func load() async {
        phase = .loading
        do {
            let page = try await source.search(preset.query())
            phase = .loaded(page.items)
            resume()
        } catch is CancellationError {
            // navigating away cancels every in-flight preset, which is ordinary
            // and not worth a line each. it arrives as either type - urlsession
            // maps its own cancellation onto NetworkError
            phase = .failed
        } catch NetworkError.cancelled {
            phase = .failed
        } catch {
            AppLog.shared.log("preset '\(preset.id)' load failed — \(error)", category: "sources")
            phase = .failed
        }
    }
}

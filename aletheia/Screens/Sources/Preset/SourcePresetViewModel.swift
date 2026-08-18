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
    // failed carries its reason rather than being a bare branch marker. the row
    // draws a full ContentUnavailableView, which has a slot for the sentence
    // under the title and an honest answer for whether to offer the retry -
    // both of which the error already knows and a payload-free case threw away
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

    // the row stops observing when it scrolls away or is navigated past, so
    // coming back has to pick the observation up again from what is already loaded
    func resume() {
        guard case .loaded(let items) = phase else { return }
        correlator.observe(items)
    }

    #if DEBUG
        // previews drive the four branches by hand rather than by loading, so the
        // one setter lives here beside the property it writes - `phase` is
        // private(set), and an extension in another file could not reach it
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
            // navigating away cancels every in-flight preset, which is ordinary
            // and not worth a line each. it arrives as either type - urlsession
            // maps its own cancellation onto NetworkError
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

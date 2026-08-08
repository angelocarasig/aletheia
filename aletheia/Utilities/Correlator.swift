//
//  Correlator.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class Correlator {
    private let database: DatabaseClient
    private let sourceSlug: String

    @ObservationIgnored private var task: Task<Void, Never>?

    private(set) var matches: [String: SeriesMatch] = [:]

    init(sourceSlug: String, database: DatabaseClient) {
        self.sourceSlug = sourceSlug
        self.database = database
    }

    subscript(stub: SeriesStub) -> SeriesMatch? {
        matches[stub.slug]
    }

    // the tracked region is defined by the fetch closure, so a changed stub list
    // needs a new observation rather than a re-fetch of the existing one
    func observe(_ stubs: [SeriesStub]) {
        task?.cancel()

        guard !stubs.isEmpty else {
            matches = [:]
            task = nil
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            for await correlated in stream(for: stubs) {
                self.matches = correlated
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func stream(for stubs: [SeriesStub]) -> AsyncStream<[String: SeriesMatch]> {
        let reader = database.reader
        let sourceSlug = sourceSlug

        return AsyncStream { continuation in
            // match skips the origin query entirely until the source row exists,
            // so the tracked region varies - trackingConstantRegion would be wrong
            let observation = ValueObservation
                .tracking { db in
                    let matched = try SeriesRecord.match(stubs, from: sourceSlug, in: db)
                    return Dictionary(
                        zip(stubs.map(\.slug), matched),
                        uniquingKeysWith: { first, _ in first }
                    )
                }
                // any write to series, origin, title or source re-runs the fetch,
                // and most of those leave every badge exactly as it was
                .removeDuplicates()

            let cancellable = observation.start(
                in: reader,
                scheduling: .immediate,
                onError: { _ in continuation.finish() },
                onChange: { continuation.yield($0) }
            )

            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

//
//  Bootstrap.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Observation

// everything the app needs standing up before its first frame, run off the main
// actor and reported phase by phase. migrations live in the opening phase, so the
// progress surface is already in place when they start taking real time
@MainActor
@Observable
final class Bootstrap {
    enum Phase: Equatable {
        case idle
        case opening
        case seeding
        case cleaning
        case ready
        case failed(Failure)

        var label: String {
            switch self {
            case .idle: "Starting"
            case .opening: "Preparing database"
            case .seeding: "Installing sources"
            case .cleaning: "Tidying up"
            case .ready: "Ready"
            case .failed: "Couldn't start"
            }
        }

        // drives a determinate bar - an indeterminate spinner says nothing about
        // how much is left, which matters once migrations are slow
        var progress: Double {
            switch self {
            case .idle: 0
            case .opening: 0.25
            case .seeding: 0.6
            case .cleaning: 0.85
            case .ready, .failed: 1
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var compositor: Compositor?

    @ObservationIgnored var bypass = Bypass()

    func run() async {
        switch phase {
        case .idle, .failed: break
        default: return
        }

        do {
            phase = .opening
            let database = try await Self.open()

            let compositor = Compositor(database: database)

            phase = .seeding
            await compositor.registry.seed()

            phase = .cleaning
            await compositor.db.clean()

            // after clean, whose cascade is what orphans the files it collects.
            // does not block the first frame - it enumerates a directory that can
            // hold thousands of entries
            compositor.assets.sweep()
            compositor.downloads.sweep()

            // registration has to complete before launch ends, and a launch the
            // system started for the task itself has no screens to do it from
            compositor.refresh.register()
            compositor.downloads.register()
            compositor.refresh.catchUp()

            // the queue is intent, and intent is what a kill destroys - the bytes
            // already on disk are picked up again for free
            compositor.downloads.restore()

            // the pending columns are durable, so anything that piled up while
            // offline drains on its own once an account is back
            compositor.trackers.hydrate()
            compositor.trackers.restore()

            await Notifier.prepare()

            self.compositor = compositor
            phase = .ready
        } catch {
            AppLog.shared.log("bootstrap FAILED - \(error)", category: "bootstrap")
            phase = .failed(Failure(error, fallback: "Couldn't Start"))
        }
    }

    // opening the pool and running the migrator are synchronous with no async
    // form, so this is the one place that genuinely has to leave the main actor
    @concurrent
    private static func open() async throws -> DatabaseClient {
        try DatabaseClient()
    }
}

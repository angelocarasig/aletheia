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
        case failed(String)

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

            self.compositor = compositor
            phase = .ready
        } catch {
            AppLog.shared.log("bootstrap FAILED — \(error)", category: "bootstrap")
            phase = .failed(error.localizedDescription)
        }
    }

    // opening the pool and running the migrator are synchronous with no async
    // form, so this is the one place that genuinely has to leave the main actor
    @concurrent
    private static func open() async throws -> DatabaseClient {
        try DatabaseClient()
    }
}

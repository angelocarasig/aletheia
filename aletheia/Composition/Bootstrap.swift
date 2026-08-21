//
//  Bootstrap.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Observation
import SwiftUI

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

        var progress: Double {
            switch self {
            case .idle: 0
            case .opening: 0.3
            case .seeding: 0.65
            case .cleaning: 0.9
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
            // Compositor.shared() is process-wide and single-flight, so this attaches
            // to a run already in flight (e.g. from a headless BGTask) instead of
            // building a second graph
            let compositor = try await Compositor.shared()

            phase = .seeding
            await compositor.registry.seed()

            phase = .cleaning
            await compositor.db.clean()

            // must run after db.clean() - its cascade is what orphans the files being swept
            compositor.assets.sweep()
            compositor.downloads.sweep()
            compositor.recommendations.sweep()

            // must complete before launch ends - a system-started BGTask launch has
            // no screen to register from later
            compositor.refresh.register()
            compositor.downloads.register()
            compositor.refresh.catchUp()
            compositor.metadata.catchUp()

            // re-armed at launch, not just end of run - a killed/crashed/jetsammed run
            // takes its pending BGTaskScheduler request with it, so without this the
            // schedule dies silently
            compositor.refresh.schedule()
            compositor.metadata.schedule()

            compositor.downloads.restore()

            compositor.trackers.hydrate()
            compositor.trackers.restore()

            await Notifier.prepare()

            self.compositor = compositor
            phase = .ready

            // warming is ~236ms of pure I/O nothing on screen waits for; .utility
            // (not .userInitiated) is deliberate so it doesn't compete with the
            // first frame's covers and the two sweeps above
            Task(priority: .utility) {
                await compositor.recommender.warm()

                // ModelBundle.probe() reloads the whole bundle and runs eleven timed
                // queries; running it before .ready froze the launch spinner ~400ms in
                // DEBUG because it's non-isolated work called without await
                #if DEBUG
                    await Task.detached { ModelBundle.probe() }.value
                    await ModelBundle.probe(compositor.recommender)
                #endif
            }
        } catch {
            AppLog.shared.log("bootstrap FAILED - \(error)", level: .error, category: "bootstrap")
            phase = .failed(Failure(error, fallback: "Couldn't Start"))
        }
    }
}

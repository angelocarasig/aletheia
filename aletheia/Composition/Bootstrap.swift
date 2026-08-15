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
            // the same instance a headless launch handler resolves - built once
            // per process by whoever asks first, so opening the app mid-run
            // attaches to the run in flight rather than constructing a second
            // graph that reports idle
            let compositor = try await Compositor.shared()

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

            // re-armed at launch as well as at the end of every run. a run that
            // never reaches its own completion - killed, crashed, jetsammed -
            // takes the pending request with it and schedules nothing in its
            // place, so without this the schedule dies silently and stays dead.
            // not on every foreground: the anchor does not move, so resubmitting
            // per activation is churn for an identical request
            compositor.refresh.schedule()

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

            // warming is 236 ms of pure I/O and nothing on screen waits for it.
            // the recommendations rail draws its own skeleton, queries off this
            // actor, and sits below the chapter list - so a launch that blocked
            // on this was holding back Home, Library, Search, Sources and the
            // reader to save a wait that only ever happened behind a shimmer
            //
            // .utility rather than .userInitiated on purpose: 116 MB of reads now
            // overlap the first frame's covers and the two sweeps, and this is
            // the one of those the user is not waiting for
            Task(priority: .utility) {
                await compositor.recommender.warm()

                // the probes re-load the whole bundle and run eleven timed
                // queries. run before .ready they froze the launch spinner for
                // ~400 ms in every DEBUG build - and being non-isolated work
                // called without await, they did it on the main actor
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

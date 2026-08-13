//
//  Compositor+Launch.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation
import BackgroundTasks

// the graph, and the one registration that cannot wait for a screen.
//
// a launch the system starts to run a scheduled task connects no window, so
// nothing a view owns is ever reached. registration has to happen during launch
// itself - the api asserts and kills the process otherwise - and the handler
// that runs later needs the same graph a foreground launch builds, not a second
// one. see docs/features/background-activity.md 4.7.1
extension Compositor {
    // built at most once per process, by whoever asks first. an actor rather
    // than a lazy var because two callers can ask at the same time: bootstrap
    // from the first frame and a launch handler from the system, and the pool
    // must not be opened twice
    private actor Builder {
        static let shared = Builder()
        private var building: Task<Compositor, Error>?

        func compositor() async throws -> Compositor {
            if let building { return try await building.value }

            let task = Task {
                // opening the pool and running the migrator are synchronous with
                // no async form, so this is the one place that has to leave the
                // main actor
                let database = try await Self.open()
                return Compositor(database: database)
            }

            building = task

            do {
                return try await task.value
            } catch {
                // a failed open must not be cached as the answer forever - the
                // retry offered on the bootstrap screen has to be able to work
                building = nil
                throw error
            }
        }

        @concurrent
        private static func open() async throws -> DatabaseClient {
            try DatabaseClient()
        }
    }

    static func shared() async throws -> Compositor {
        try await Builder.shared.compositor()
    }
}

// MARK: - Launch registration

@MainActor
enum Launch {
    // the api kills the app on a second registration of the same identifier, and
    // swiftui gives no contract on how many times an app value is initialised
    private static var registered = false

    // called from the app delegate, which runs on every launch including one the
    // system starts headlessly. graph-free on purpose: the work of building it
    // belongs to the handler, which runs later and can await
    static func registerScheduledRefresh(log: AppLog = .shared) {
        guard !registered else { return }
        registered = true

        #if !targetEnvironment(simulator)
        // a different api from the continued-processing tasks, and a different
        // rule: those are exempt from having to register before launch ends, so
        // they stay with the owner that submits them. this one is not
        let installed = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.Tasks.scheduledRefresh,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let compositor = try? await Compositor.shared() else {
                    log.log("scheduled refresh could not build the graph", level: .error, category: "refresh")
                    return task.setTaskCompleted(success: false)
                }

                compositor.refresh.adopt(task)
            }
        }

        // false means the identifier is missing from BGTaskSchedulerPermittedIdentifiers,
        // which is the one failure this call reports rather than asserting on
        log.log(
            installed
                ? "registered \(Constants.Tasks.scheduledRefresh)"
                : "\(Constants.Tasks.scheduledRefresh) refused - identifier not permitted",
            level: installed ? .info : .error,
            category: "tasks"
        )
        #endif
    }
}

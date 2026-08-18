//
//  Compositor+Launch.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import BackgroundTasks
import Foundation

// BGTaskScheduler registration must happen during launch itself - the api
// asserts and kills the process otherwise - see docs/features/background-activity.md 4.7.1
extension Compositor {
    // actor rather than a lazy var: bootstrap and a system launch handler can
    // both ask for this at the same time, and the pool must not be opened twice
    private actor Builder {
        static let shared = Builder()
        private var building: Task<Compositor, Error>?

        func compositor() async throws -> Compositor {
            if let building { return try await building.value }

            let task = Task {
                // opening the pool and running the migrator are synchronous, so this
                // is the one place that has to leave the main actor
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

    // graph-free on purpose: registration must be synchronous, so building the
    // graph is deferred to the handler closure below, which runs later and can await
    static func registerScheduledRefresh(log: AppLog = .shared) {
        guard !registered else { return }
        registered = true

        #if !targetEnvironment(simulator)
            // unlike continued-processing tasks (exempt from launch-time
            // registration), a BGTaskScheduler identifier must register before launch ends
            let installed = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Constants.Tasks.scheduledRefresh,
                using: nil
            ) { task in
                Task { @MainActor in
                    guard let compositor = try? await Compositor.shared() else {
                        log.log(
                            "scheduled refresh could not build the graph", level: .error,
                            category: "refresh")
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

    private static var registeredMetadata = false

    static func registerScheduledMetadataRefresh(log: AppLog = .shared) {
        guard !registeredMetadata else { return }
        registeredMetadata = true

        #if !targetEnvironment(simulator)
            let installed = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Constants.Tasks.scheduledMetadataRefresh,
                using: nil
            ) { task in
                Task { @MainActor in
                    guard let compositor = try? await Compositor.shared() else {
                        log.log(
                            "scheduled metadata refresh could not build the graph", level: .error,
                            category: "metadata")
                        return task.setTaskCompleted(success: false)
                    }

                    compositor.metadata.adopt(task)
                }
            }

            log.log(
                installed
                    ? "registered \(Constants.Tasks.scheduledMetadataRefresh)"
                    : "\(Constants.Tasks.scheduledMetadataRefresh) refused - identifier not permitted",
                level: installed ? .info : .error,
                category: "tasks"
            )
        #endif
    }
}

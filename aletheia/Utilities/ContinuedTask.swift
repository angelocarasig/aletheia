//
//  ContinuedTask.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation
import BackgroundTasks

// the half of a BGContinuedProcessingTask that is the same for every operation:
// registering an identifier, asking for the task, attaching one the system grants
// mid-run, and keeping its progress moving. what differs is only how far along the
// owner is, which arrives through one closure.
//
// there is no apple protocol for this. NSProgressReporting says "i have a
// Progress" and nothing about registration, submission or expiry, and the task's
// own progress is read-only, so an owner cannot hand over one of its own
@MainActor
final class ContinuedTask {
    // the owner's own numbers, already scaled however it scales them. nil means
    // the run is over, which is the only thing this type needs to know about it
    struct Tick: Sendable {
        let done: Int64
        let total: Int64
        let subtitle: String
    }

    private let identifier: String
    private let tick: @MainActor () -> Tick?
    // the owner nudging whatever it drifts between real completions. runs on the
    // heartbeat, immediately before the progress it feeds
    private let drift: @MainActor () -> Void
    private let log: AppLog

    private var task: BGContinuedProcessingTask?
    private var heart: Task<Void, Never>?

    // comfortably inside the ~30s cadence window the system enforces, with room
    // for a tick to be missed
    private static let beat: Duration = .seconds(5)

    // nonisolated so an owner built off the main actor during bootstrap can hold
    // one. legal because it only assigns stored properties
    nonisolated init(
        identifier: String,
        log: AppLog = .shared,
        tick: @escaping @MainActor () -> Tick?,
        drift: @escaping @MainActor () -> Void = {}
    ) {
        self.identifier = identifier
        self.log = log
        self.tick = tick
        self.drift = drift
    }

    // registration has to complete before launch ends, and a launch the system
    // started for the task itself has no screens to do it from
    nonisolated func register(onExpire: @escaping @MainActor () -> Void) {
        #if !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in self?.adopt(task, onExpire: onExpire) }
        }

        log.log("registered \(identifier)", category: "tasks")
        #endif
    }

    func submit(title: String, subtitle: String) {
        // one live task per identifier: a run that picks up more work mid-flight
        // extends the task it already holds rather than asking for a second
        guard task == nil else {
            log.log("\(identifier) already live, not submitting again", category: "tasks")
            return
        }

        #if targetEnvironment(simulator)
        log.log("\(identifier) not submitted - simulator has no continued-processing tasks", category: "tasks")
        #else
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: subtitle
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            log.log("submitted \(identifier) - \"\(title)\" / \"\(subtitle)\"", category: "tasks")
        } catch {
            // a failed submission is not a failed run: the work is already going
            // in the foreground, it simply will not survive being backgrounded
            log.log("continued-processing task not granted - \(error)", category: "tasks")
        }
        #endif
    }

    func advance() {
        guard let task, let now = tick(), now.total > 0 else { return }

        task.progress.totalUnitCount = now.total
        task.progress.completedUnitCount = min(now.done, now.total)
        task.updateTitle(task.title, subtitle: now.subtitle)
    }

    func finish() {
        if task != nil { log.log("finished \(identifier)", category: "tasks") }
        heart?.cancel()
        heart = nil
        task?.setTaskCompleted(success: true)
        task = nil
    }

    // MARK: Private

    // the system granted the task after the work was already going, so this
    // attaches rather than starts. a run that finished in the meantime completes
    // it immediately - there is nothing left to extend
    private func adopt(_ task: BGContinuedProcessingTask, onExpire: @escaping @MainActor () -> Void) {
        guard tick() != nil else {
            log.log("granted \(identifier) after the run ended - completing it", category: "tasks")
            task.setTaskCompleted(success: true)
            return
        }

        task.expirationHandler = { [log, identifier] in
            // cancel, system pressure and failure all arrive here identically -
            // the api cannot say which, so neither can we
            log.log("\(identifier) expired", category: "tasks")
            Task { @MainActor in onExpire() }
        }

        log.log("adopted \(identifier)", category: "tasks")
        self.task = task
        beat()
        advance()
    }

    // the periodic sleep is a heartbeat, not a delay waiting on state to settle:
    // the tick IS the signal the system asks for, and a run whose counter has not
    // moved in about thirty seconds is expired without being told why
    private func beat() {
        heart?.cancel()
        heart = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.beat)
                guard let self, self.tick() != nil, !Task.isCancelled else { return }

                self.drift()
                self.advance()
            }
        }
    }
}

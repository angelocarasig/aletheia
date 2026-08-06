//
//  RequestThrottler.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

/// actor-based request throttler that limits concurrent requests and staggers them with delays
/// prevents overwhelming backend services with too many simultaneous requests
actor RequestThrottler {
    private let maxConcurrent: Int
    private let staggerDelay: Duration
    private let timeout: Duration

    private var activeCount: Int = 0
    private var waitingTasks: [CheckedContinuation<Void, Never>] = []

    static let shared = RequestThrottler(
        maxConcurrent: 5,
        staggerDelay: .milliseconds(500),
        timeout: .seconds(3)
    )

    init(maxConcurrent: Int, staggerDelay: Duration, timeout: Duration = .seconds(12)) {
        self.maxConcurrent = maxConcurrent
        self.staggerDelay = staggerDelay
        self.timeout = timeout
    }

    /// executes a request with throttling and timeout
    /// requests wait in a queue if concurrent limit is reached
    /// each request is staggered by the configured delay
    /// throws NetworkError.timeout if operation exceeds timeout duration
    func execute<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        // wait for available slot
        await waitForSlot()

        // check for cancellation after acquiring slot
        try Task.checkCancellation()

        // stagger the request
        do {
            try await Task.sleep(for: staggerDelay)
        } catch {
            // if cancelled during sleep, release slot immediately
            releaseSlot()
            throw error
        }

        // check for cancellation after sleep
        do {
            try Task.checkCancellation()
        } catch {
            releaseSlot()
            throw error
        }

        // execute the operation with timeout
        defer {
            releaseSlot()
        }

        return try await withThrowingTaskGroup(of: T.self) { group in
            // add the actual operation
            group.addTask {
                try await operation()
            }

            // add timeout task
            group.addTask {
                try await Task.sleep(for: self.timeout)
                throw NetworkError.timeout
            }

            // race: return first result
            guard let result = try await group.next() else {
                throw NetworkError.timeout
            }

            // cancel the other task
            group.cancelAll()

            return result
        }
    }

    private func waitForSlot() async {
        // if under limit, proceed immediately
        guard activeCount >= maxConcurrent else {
            activeCount += 1
            return
        }

        // otherwise, wait in queue
        await withCheckedContinuation { continuation in
            waitingTasks.append(continuation)
        }

        activeCount += 1
    }

    private func releaseSlot() {
        activeCount -= 1

        // resume next waiting task if any
        if !waitingTasks.isEmpty {
            let next = waitingTasks.removeFirst()
            next.resume()
        }
    }
}

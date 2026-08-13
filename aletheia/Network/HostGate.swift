//
//  HostGate.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

// bounds how many requests are in flight at one host. it sits inside
// NetworkService because that is the single funnel every request already passes
// through - sources, page and cover downloads, and authenticated sends - so no
// call site has to remember to be polite, and none can opt out.
//
// the key is the host rather than a source id: a site is what notices, and a
// source id is our own rowid. see docs/features/background-activity.md 8.2.1
actor HostGate {
    private let limit: Int
    private let overrides: [String: Int]
    private let log: AppLog
    private var active: [String: Int] = [:]
    private var waiting: [String: [Waiter]] = [:]
    // both a hand-off and a cancellation resume the continuation and remove the
    // waiter, so the queue alone cannot say which woke you. membership here does
    private var granted: Set<UUID> = []

    init(
        limit: Int = Constants.Network.requestsPerHost,
        overrides: [String: Int] = Constants.Network.requestsPerHostOverrides,
        log: AppLog = .shared
    ) {
        self.limit = limit
        self.overrides = overrides
        self.log = log
    }

    // a site whose own architecture serialises us gains nothing from a wider
    // bucket and loses tail latency to it
    private func limit(for host: String) -> Int {
        overrides[host] ?? limit
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    func execute<T: Sendable>(
        host: String?,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        // a url with no host cannot be attributed to anyone, so it is not gated
        // rather than being lumped under a shared empty key
        guard let host, !host.isEmpty else {
            return try await operation()
        }

        guard await acquire(host) else { throw CancellationError() }
        defer { release(host) }

        return try await operation()
    }

    // false means the wait ended in cancellation rather than a free slot, so the
    // caller holds nothing and must not release
    private func acquire(_ host: String) async -> Bool {
        let count = active[host] ?? 0
        if count < limit(for: host) {
            active[host] = count + 1
            return true
        }

        let id = UUID()

        // the only unbounded wait on the request path - every timeout in the app
        // is on the request itself, which has not been made yet. so a starved
        // queue is indistinguishable from a slow site unless it says so
        let queued = Date.now
        let depth = (waiting[host]?.count ?? 0) + 1
        let watchdog = Task { [log] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            log.log(
                "waiting on \(host) for 5s+ - \(depth) deep, \(self.limit(for: host)) slot(s)",
                level: .warning,
                category: "network"
            )
        }
        defer {
            watchdog.cancel()
            let held = Date.now.timeIntervalSince(queued)
            if held >= 5 {
                log.log("released onto \(host) after \(Int(held))s", level: .warning, category: "network")
            }
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // the handler is armed before this runs, so a cancellation that
                // lands in between finds nothing to remove - this check is what
                // stops that task parking forever
                if Task.isCancelled {
                    continuation.resume()
                    return
                }
                waiting[host, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.abandon(id, host: host) }
        }

        let holdsSlot = granted.remove(id) != nil

        // cancellation can also land after the hand-off, so owning a slot and
        // being cancelled are not exclusive - give it straight back
        if Task.isCancelled {
            if holdsSlot { release(host) }
            return false
        }
        return holdsSlot
    }

    // the slot is handed to the next waiter rather than released and re-taken:
    // decrementing first leaves a gap a newcomer can walk into, which is how the
    // old RequestThrottler over-subscribed its own limit
    private func release(_ host: String) {
        if var queue = waiting[host], !queue.isEmpty {
            let next = queue.removeFirst()
            waiting[host] = queue.isEmpty ? nil : queue
            granted.insert(next.id)
            next.continuation.resume()
            return
        }

        let count = (active[host] ?? 1) - 1
        active[host] = count > 0 ? count : nil
    }

    // a waiter already handed a slot is no longer in the queue, so a cancellation
    // arriving after the hand-off finds nothing and cannot resume it twice
    private func abandon(_ id: UUID, host: String) {
        guard var queue = waiting[host], let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        waiting[host] = queue.isEmpty ? nil : queue
        waiter.continuation.resume()
    }
}

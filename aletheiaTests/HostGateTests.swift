//
//  HostGateTests.swift
//  aletheiaTests
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Testing
import Foundation
@testable import aletheia

// the gate is the piece most worth a test and the least amenable to reading:
// its correctness lives in what happens between a slot being freed and the next
// waiter taking it, which no amount of staring at the code settles.
// see docs/features/background-activity.md 8.2.1
@Suite("HostGate")
struct HostGateTests {

    // counts how many operations were inside the gate at once, which is the only
    // property that actually matters
    actor Peak {
        private var current = 0
        private(set) var highest = 0

        func enter() {
            current += 1
            highest = max(highest, current)
        }

        func leave() {
            current -= 1
        }
    }

    // parks until opened, so a test can hold slots without guessing at durations
    actor Latch {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var opened = false

        func wait() async {
            guard !opened else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            opened = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    @Test("never lets more than the limit through at one host")
    func respectsLimit() async throws {
        let gate = HostGate(limit: 3)
        let peak = Peak()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try? await gate.execute(host: "example.com") {
                        await peak.enter()
                        // long enough that the tasks genuinely overlap; without
                        // this they can serialise and the test proves nothing
                        try? await Task.sleep(for: .milliseconds(20))
                        await peak.leave()
                    }
                }
            }
        }

        #expect(await peak.highest <= 3)
    }

    // the hand-off is what this is really testing: releasing a slot and letting
    // the waiter re-take it leaves a gap a newcomer can walk into, which is how
    // the throttler this replaced over-subscribed its own limit
    @Test("a freed slot goes to a waiter, not to whoever arrives next")
    func handsOffWithoutAGap() async throws {
        let gate = HostGate(limit: 1)
        let peak = Peak()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? await gate.execute(host: "example.com") {
                        await peak.enter()
                        try? await Task.sleep(for: .milliseconds(10))
                        await peak.leave()
                    }
                }
            }
        }

        #expect(await peak.highest == 1)
    }

    @Test("hosts do not block each other")
    func separatesHosts() async throws {
        let gate = HostGate(limit: 1)
        let peak = Peak()

        await withTaskGroup(of: Void.self) { group in
            for host in ["a.example", "b.example", "c.example"] {
                group.addTask {
                    try? await gate.execute(host: host) {
                        await peak.enter()
                        try? await Task.sleep(for: .milliseconds(30))
                        await peak.leave()
                    }
                }
            }
        }

        // one each, all at once - a global limit would serialise these
        #expect(await peak.highest == 3)
    }

    @Test("a url with no host is not gated")
    func passesHostlessThrough() async throws {
        let gate = HostGate(limit: 1)
        let latch = Latch()

        // the occupant holds the only slot for the duration
        let occupant = Task {
            try? await gate.execute(host: "example.com") { await latch.wait() }
        }

        var ran = false
        try await gate.execute(host: nil) { ran = true }
        #expect(ran)

        await latch.open()
        await occupant.value
    }

    // the defect that mattered most: a task cancelled while parked used to never
    // be resumed, so it hung forever and its continuation leaked
    @Test("cancelling while parked throws instead of hanging")
    func cancellationReleasesAWaiter() async throws {
        let gate = HostGate(limit: 1)
        let latch = Latch()
        let occupied = Latch()

        let occupant = Task {
            try? await gate.execute(host: "example.com") {
                await occupied.open()
                await latch.wait()
            }
        }
        await occupied.wait()

        let waiter = Task {
            try await gate.execute(host: "example.com") { }
        }
        // the waiter needs to have reached the queue before it is cancelled;
        // there is no signal for "is parked", so this is the one place the test
        // has to wait on a duration
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()

        await #expect(throws: CancellationError.self) { try await waiter.value }

        await latch.open()
        await occupant.value

        // and the slot it never held was not double-released: the gate still
        // works, and still bounds itself
        let peak = Peak()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await gate.execute(host: "example.com") {
                        await peak.enter()
                        try? await Task.sleep(for: .milliseconds(10))
                        await peak.leave()
                    }
                }
            }
        }
        #expect(await peak.highest == 1)
    }
}

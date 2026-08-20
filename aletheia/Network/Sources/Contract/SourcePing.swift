//
//  SourcePing.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

enum PingStatus: Sendable {
    case healthy
    case slow
    case down
}

struct PingResult: Sendable {
    let status: PingStatus
    let latency: Duration?
}

extension SourceService {
    var pingURL: URL { descriptor.baseURL }

    // network is passed in, never defaulted - `= NetworkService()` used to
    // construct one PER CALL, so a screen of seven source rows built seven
    // URLSessions and seven HostGates, defeating the 3-per-host cap entirely
    func ping(using network: NetworkConfiguration) async -> PingResult {
        let clock = ContinuousClock()
        let start = clock.now

        // the cached credential only, never a refresh - a ping triggering a
        // verification sheet on a screen the reader only opened to browse would
        // be a bad surprise; a source behind a wall just reads red until then
        var request = URLRequest(url: pingURL)
        if let authenticating = self as? any AuthenticatingSource,
            let credential = await authenticating.requester.peek(slug: descriptor.slug)
        {
            credential.apply(to: &request)
        }

        let outgoing = request

        do {
            let response = try await withDeadline(Constants.Network.pingTimeout) {
                try await network.send(outgoing).1
            }
            let elapsed = clock.now - start

            guard (200..<300).contains(response.statusCode) else {
                return PingResult(status: .down, latency: nil)
            }
            let status: PingStatus = elapsed < .milliseconds(500) ? .healthy : .slow
            return PingResult(status: status, latency: elapsed)
        } catch {
            return PingResult(status: .down, latency: nil)
        }
    }
}

// URLRequest.timeoutInterval cannot shorten a request made by a session that
// carries its own timeoutIntervalForRequest - the session's value wins, so a
// ping asking for 1.5s waited the full 30s. racing against a sleeping task is
// the only way a caller can impose its own deadline on a shared session
private func withDeadline<Value: Sendable>(
    _ limit: Duration,
    _ work: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw CancellationError()
        }

        let first = try await group.next()!
        group.cancelAll()
        return first
    }
}

extension Duration {
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(Double(seconds) * 1000 + Double(attoseconds) * 1e-15)
    }
}

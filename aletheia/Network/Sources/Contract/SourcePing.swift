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

    // the network is passed in, never defaulted. it used to read
    // `= NetworkService()`, which constructs one PER CALL - so a screen of seven
    // source rows built seven URLSessions and seven HostGates, and the 3-per-host
    // cap meant nothing at exactly the moment the app was touching seven hosts
    // at once
    func ping(using network: NetworkConfiguration) async -> PingResult {
        let clock = ContinuousClock()
        let start = clock.now

        // the cached credential, never a refresh - same rule as
        // SourceService.requestHeaders. a screen of source rows pings every row
        // it draws, and a capture from there would put a verification sheet in
        // front of a reader who only opened a list. so a source behind a wall
        // reads red until something they actually asked for earns the cookies,
        // which is the honest answer anyway: until then we cannot reach it
        var request = URLRequest(url: pingURL)
        if let authenticating = self as? any AuthenticatingSource,
            let credential = await authenticating.requester.peek(slug: descriptor.slug)
        {
            credential.apply(to: &request)
        }

        do {
            let response = try await withDeadline(Constants.Network.pingTimeout) {
                try await network.send(request).1
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
// ping asking for 1.5s waited the full 30 and a dead source's row sat spinning
// for half a minute. a race is the only way a CALLER can impose a deadline on a
// shared session, and it works because URLSession honours task cancellation
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

        // whichever finishes first, then the other is cancelled on the way out
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

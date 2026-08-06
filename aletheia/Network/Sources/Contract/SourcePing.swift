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
    func ping(using network: NetworkConfiguration = NetworkService()) async -> PingResult {
        var request = URLRequest(url: descriptor.baseURL)
        request.timeoutInterval = 1.5

        let clock = ContinuousClock()
        let start = clock.now

        do {
            let (_, response) = try await network.send(request)
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

extension Duration {
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(Double(seconds) * 1000 + Double(attoseconds) * 1e-15)
    }
}

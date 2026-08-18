//
//  SourceHomeViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class SourceHomeViewModel {
    private let source: Source
    private let requester: AuthRequester

    private(set) var heroEntries: [SeriesStub] = []
    private(set) var isLoadingHero = true

    // when the credential was last earned, not when its cookie claims to expire.
    // every cf_clearance declares 365 days and none of them lasts an hour, so a
    // countdown off that date told the reader a year of health about something
    // that had already stopped working. "captured 3m ago" is a fact we own
    private(set) var credentialCaptured: Date?
    private(set) var isRefreshingCredential = false

    var isAuthenticating: Bool { source is AuthenticatingSource }

    private enum Limit {
        static let heroCovers = 8
        static let presetSpread = 3
    }

    init(source: Source, requester: AuthRequester) {
        self.source = source
        self.requester = requester
    }

    func loadCredential() async {
        guard isAuthenticating else { return }
        credentialCaptured = await requester.peek(slug: source.descriptor.slug)?.capturedDate
    }

    func refreshCredential() async {
        guard let auth = source as? AuthenticatingSource, !isRefreshingCredential else { return }
        isRefreshingCredential = true
        defer { isRefreshingCredential = false }
        do {
            let credential = try await requester.forceRefresh(for: auth)
            credentialCaptured = credential.capturedDate
        } catch {
            AppLog.shared.log(
                "credential refresh failed for '\(source.descriptor.slug)' - \(error)",
                level: .error, category: "auth")
        }
    }

    func loadHero() async {
        guard heroEntries.isEmpty else { return }

        let presets = source.presets
            .filter { !$0.hidden }
            .sorted { $0.order < $1.order }
            .prefix(Limit.presetSpread)

        guard !presets.isEmpty else {
            isLoadingHero = false
            return
        }

        let source = source
        let pages = await withTaskGroup(of: [SeriesStub].self) { group in
            for preset in presets {
                group.addTask {
                    (try? await source.search(preset.query()))?.items ?? []
                }
            }
            var all: [SeriesStub] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }

        heroEntries = Self.sample(from: pages, seed: daySeed, count: Limit.heroCovers)
        isLoadingHero = false
    }

    // unique series with covers, deterministically shuffled so the selection is
    // stable within a day (per source) and rotates daily.
    private static func sample(from stubs: [SeriesStub], seed: UInt64, count: Int) -> [SeriesStub] {
        var seen = Set<String>()
        let unique = stubs.filter { $0.cover != nil && seen.insert($0.slug).inserted }

        var generator = SeededGenerator(seed: seed)
        return Array(unique.shuffled(using: &generator).prefix(count))
    }

    private var daySeed: UInt64 {
        let day = UInt64(Date().timeIntervalSince1970 / 86_400)
        return day ^ source.descriptor.slug.stableHash
    }
}

// MARK: - Seeded Randomness

// canonical SplitMix64: the standard seedable generator (also what's used to
// seed xoshiro). well-distributed from any seed including 0, so no guard needed.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Stable Hashing

extension String {
    // FNV-1a (64-bit). deterministic across launches, unlike String.hashValue
    // which Swift randomizes per process - the day-seeded hero selection needs a
    // launch-stable seed so it stays fixed for the whole day.
    fileprivate var stableHash: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return hash
    }
}

//
//  Compositor+Privacy.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Foundation
import LocalAuthentication
import Observation

extension Compositor {
    // in-memory only, on purpose - unlocking a collection or source is a
    // per-session decision, not a persisted preference, so it resets on
    // every app relaunch without any extra bookkeeping
    @MainActor
    @Observable
    final class Privacy {
        private(set) var unlockedCollections: Set<CollectionRecord.ID> = []
        private(set) var unlockedSources: Set<SourceRecord.ID> = []

        // nonisolated so Compositor can build this off the main actor during
        // bootstrap, same reasoning as Compositor.Downloads' own init
        nonisolated init() {}

        func isUnlocked(_ id: CollectionRecord.ID) -> Bool {
            unlockedCollections.contains(id)
        }

        func isUnlocked(_ id: SourceRecord.ID) -> Bool {
            unlockedSources.contains(id)
        }

        func unlock(_ id: CollectionRecord.ID) async -> Bool {
            guard await authenticate(reason: "Unlock this collection") else { return false }
            unlockedCollections.insert(id)
            return true
        }

        func unlock(_ id: SourceRecord.ID) async -> Bool {
            guard await authenticate(reason: "Unlock this source") else { return false }
            unlockedSources.insert(id)
            return true
        }

        // a fresh LAContext per attempt - one is spent after it resolves once,
        // not meant to be reused across separate evaluations
        private func authenticate(reason: String) async -> Bool {
            let context = LAContext()
            var error: NSError?

            guard
                context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            else { return false }

            return await withCheckedContinuation { continuation in
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
                    success, _ in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

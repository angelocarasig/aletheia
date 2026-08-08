//
//  Bootstrap+Bypass.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/26.
//

import Foundation

extension Bootstrap {
    struct Bypass {
        private static let taps = 10
        private static let window: TimeInterval = 0.6

        private var count = 0
        private var lastTapDate = Date.distantPast

        mutating func registerTap(now: Date = .now) {
            count = now.timeIntervalSince(lastTapDate) <= Self.window ? count + 1 : 1
            lastTapDate = now

            guard count >= Self.taps else { return }
            count = 0

            let defaults = UserDefaults.standard
            defaults.set(
                !defaults.bool(forKey: Preferences.Key.bypassAdultSources),
                forKey: Preferences.Key.bypassAdultSources
            )
            BypassHaptic.play()
        }
    }
}

//
//  Refresh.swift
//  aletheia
//
//  Created by Angelo Carasig on 11/8/2026.
//

import Foundation

extension Constants {
    enum Refresh {
        // deliberately not Preferences.Key.refreshInterval - that one is the
        // background walk's cadence and defaults to off, so binding to it
        // would disable this for most readers
        static let staleAfter: TimeInterval = 3 * 24 * 60 * 60

        // not a cadence - ios runs a processing task when idle and charging,
        // in practice once a night, and that timing isn't ours to choose.
        // this only says how often we're willing to ask
        static let automaticInterval: TimeInterval = 12 * 60 * 60
    }
}

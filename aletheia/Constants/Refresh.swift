//
//  Refresh.swift
//  aletheia
//
//  Created by Angelo Carasig on 11/8/2026.
//

import Foundation

extension Constants {
    enum Refresh {
        // how old a chapter list may be before opening the series from a source
        // re-checks it. deliberately not Preferences.Key.refreshInterval: that
        // one is the background walk's cadence and defaults to off, so binding
        // to it would disable this for most readers. this is a different
        // question - the reader is online, looking at a source's catalogue, and
        // asked for this series by name
        static let staleAfter: TimeInterval = 3 * 24 * 60 * 60

        // the floor an automatic run is submitted behind, and the age that makes
        // the foreground catch-up fire. not a cadence: ios runs a processing task
        // when the device is idle and charging, which in practice is once a night
        // and is not ours to choose. this only says how often we are willing to
        // ask, and twelve hours is what suwayomi settled on for the same question
        static let automaticInterval: TimeInterval = 12 * 60 * 60
    }
}

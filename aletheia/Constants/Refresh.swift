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
    }
}

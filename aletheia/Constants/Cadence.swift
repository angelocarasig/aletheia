//
//  Cadence.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Foundation

extension Constants {
    enum Cadence {
        // every source falls back to .distantPast when it cannot parse a date, so
        // one unparsed chapter would otherwise inject a ~730,000 day gap and
        // become the predicted interval. anything at or below this is a parse
        // failure rather than a release - the oldest real scanlation predates
        // 1970 nowhere
        static let epoch = Date(timeIntervalSince1970: 0)
    }
}

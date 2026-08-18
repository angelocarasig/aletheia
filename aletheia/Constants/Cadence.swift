//
//  Cadence.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Foundation

extension Constants {
    enum Cadence {
        // sources fall back to .distantPast on an unparsed date, which would
        // otherwise inject a ~730,000 day gap into the predicted interval -
        // anything at or below this is treated as a parse failure, not a release
        static let epoch = Date(timeIntervalSince1970: 0)
    }
}

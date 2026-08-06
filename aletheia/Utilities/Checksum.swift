//
//  Checksum.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import CryptoKit

enum Checksum {
    static func hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

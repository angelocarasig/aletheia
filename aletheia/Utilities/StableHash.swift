//
//  StableHash.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// deterministic across launches and platforms, unlike Swift's own Hasher,
// which is randomised per process - anything persisted or matched against a
// value computed elsewhere (a lookup table built on another machine, a
// fingerprint written to disk) needs this instead
//
// algorithm is 64-bit FNV-1a over utf-8 bytes: the export chose it over
// anything stronger because this side has to reproduce it exactly and it is
// ten lines with no dependencies - the v01 alias table ships 1.19M keys as
// hashes rather than text, which is 9.5 MB instead of 37.9 MB
//
// the arithmetic wraps by design, so every operation here is the overflow
// variant. a plain * would trap on the first byte
enum StableHash {
    private static let offset: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    static func hash(_ value: String) -> UInt64 {
        var h = offset
        for byte in value.utf8 {
            h ^= UInt64(byte)
            h = h &* prime
        }
        return h
    }
}

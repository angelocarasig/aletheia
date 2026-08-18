//
//  LibraryBackupCodec.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import SwiftProtobuf

// the one seam Export and Import both call through - neither side touches
// LibraryBackupEnvelope or protobuf serialization directly. version
// dispatch lives here: today there is only v1, so decode is a straight
// parse, but a future semantic bump (docs/features/library-backup.md §4)
// adds a case here rather than editing this one
enum LibraryBackupCodec {
    enum CodecError: Error {
        case unsupportedVersion(UInt16)
    }

    static func encode(_ message: LibraryBackup) throws -> Data {
        try LibraryBackupEnvelope.wrap(try message.serializedData())
    }

    static func decode(_ data: Data) throws -> LibraryBackup {
        let (version, payload) = try LibraryBackupEnvelope.unwrap(data)

        switch version {
        case 1:
            return try LibraryBackup(serializedBytes: payload)
        default:
            // unreachable while currentVersion == 1 - unwrap already rejects
            // anything newer. kept explicit so the next version has an
            // obvious slot to land in rather than a silent fallthrough
            throw CodecError.unsupportedVersion(version)
        }
    }
}

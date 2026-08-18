//
//  LibraryBackupCodec.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import SwiftProtobuf

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
            throw CodecError.unsupportedVersion(version)
        }
    }
}

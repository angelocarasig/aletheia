//
//  LibraryBackupEnvelope.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation
import zlib

//   [4 bytes] magic:         "ALTH"
//   [2 bytes] version:       UInt16, big-endian
//   [4 bytes] originalSize:  UInt32, big-endian (zlib's uncompress needs
//                            the output size up front)
//   [N bytes] zlib-deflated LibraryBackup protobuf message
enum LibraryBackupEnvelope {
    static let currentVersion: UInt16 = 1

    private static let magic: [UInt8] = Array("ALTH".utf8)
    private static let headerSize = 10 // magic(4) + version(2) + originalSize(4)

    enum EnvelopeError: Error, Equatable {
        case truncated
        case badMagic
        case newerVersion(UInt16)
        case compressionFailed
    }

    static func wrap(_ payload: Data, version: UInt16 = currentVersion) throws -> Data {
        var header = Data(magic)
        header.append(contentsOf: bigEndianBytes(version))
        header.append(contentsOf: bigEndianBytes(UInt32(payload.count)))
        return header + (try deflate(payload))
    }

    static func unwrap(_ data: Data) throws -> (version: UInt16, payload: Data) {
        guard data.count >= headerSize else { throw EnvelopeError.truncated }
        let bytes = [UInt8](data)

        guard Array(bytes[0..<4]) == magic else { throw EnvelopeError.badMagic }

        let version = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        guard version <= currentVersion else { throw EnvelopeError.newerVersion(version) }

        let originalSize = UInt32(bytes[6]) << 24 | UInt32(bytes[7]) << 16
            | UInt32(bytes[8]) << 8 | UInt32(bytes[9])

        let compressed = data.suffix(from: data.startIndex + headerSize)
        let payload = try inflate(compressed, originalSize: Int(originalSize))
        return (version, payload)
    }

    private static func bigEndianBytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func deflate(_ source: Data) throws -> Data {
        guard !source.isEmpty else { return Data() }

        var destLen = uLongf(compressBound(uLong(source.count)))
        var dest = [UInt8](repeating: 0, count: Int(destLen))

        let result = source.withUnsafeBytes { sourceBuffer -> Int32 in
            dest.withUnsafeMutableBufferPointer { destBuffer in
                compress2(
                    destBuffer.baseAddress,
                    &destLen,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                    uLong(source.count),
                    Z_BEST_COMPRESSION
                )
            }
        }

        guard result == Z_OK else { throw EnvelopeError.compressionFailed }
        return Data(dest.prefix(Int(destLen)))
    }

    private static func inflate(_ source: Data, originalSize: Int) throws -> Data {
        guard originalSize > 0 else { return Data() }

        var destLen = uLongf(originalSize)
        var dest = [UInt8](repeating: 0, count: originalSize)

        let result = source.withUnsafeBytes { sourceBuffer -> Int32 in
            dest.withUnsafeMutableBufferPointer { destBuffer in
                uncompress(
                    destBuffer.baseAddress,
                    &destLen,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                    uLong(source.count)
                )
            }
        }

        guard result == Z_OK, Int(destLen) == originalSize else { throw EnvelopeError.compressionFailed }
        return Data(dest)
    }
}

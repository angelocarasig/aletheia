//
//  NumpyZipReader.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// student-linear.npz and cover-projection.npz are the only zip-packaged files in the pack,
// and both are ZIP_STORED (numpy's savez default) - confirmed against the real files. this
// reads the central directory to locate named entries and returns their raw bytes directly;
// there is no decompression step, and none is added speculatively
enum NumpyZipReader {
    static func entries(in data: Data, named names: Set<String>) throws -> [String: Data] {
        guard data.count >= 22 else { throw NumpyZipError.notAZip }

        let eocdOffset = data.endIndex - 22
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard data[eocdOffset..<eocdOffset + 4].elementsEqual(eocdSignature) else {
            throw NumpyZipError.notAZip
        }

        let centralDirOffset =
            Int(data[eocdOffset + 16]) | (Int(data[eocdOffset + 17]) << 8)
            | (Int(data[eocdOffset + 18]) << 16) | (Int(data[eocdOffset + 19]) << 24)
        let centralDirSize =
            Int(data[eocdOffset + 12]) | (Int(data[eocdOffset + 13]) << 8)
            | (Int(data[eocdOffset + 14]) << 16) | (Int(data[eocdOffset + 15]) << 24)

        var found: [String: Data] = [:]
        var cursor = data.startIndex + centralDirOffset
        let centralDirEnd = cursor + centralDirSize
        let centralSignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]

        while cursor < centralDirEnd, found.count < names.count {
            guard data[cursor..<cursor + 4].elementsEqual(centralSignature) else {
                throw NumpyZipError.notAZip
            }
            let compressionMethod = Int(data[cursor + 10]) | (Int(data[cursor + 11]) << 8)
            let uncompressedSize =
                Int(data[cursor + 24]) | (Int(data[cursor + 25]) << 8)
                | (Int(data[cursor + 26]) << 16) | (Int(data[cursor + 27]) << 24)
            let nameLen = Int(data[cursor + 28]) | (Int(data[cursor + 29]) << 8)
            let extraLen = Int(data[cursor + 30]) | (Int(data[cursor + 31]) << 8)
            let commentLen = Int(data[cursor + 32]) | (Int(data[cursor + 33]) << 8)
            let localHeaderOffset =
                Int(data[cursor + 42]) | (Int(data[cursor + 43]) << 8)
                | (Int(data[cursor + 44]) << 16) | (Int(data[cursor + 45]) << 24)

            let nameStart = cursor + 46
            let name = String(data: data[nameStart..<nameStart + nameLen], encoding: .ascii) ?? ""

            if names.contains(name) {
                guard compressionMethod == 0 else { throw NumpyZipError.compressedEntry(name) }
                let payload = try readLocalEntry(
                    in: data, at: data.startIndex + localHeaderOffset,
                    uncompressedSize: uncompressedSize)
                found[name] = payload
            }

            cursor = nameStart + nameLen + extraLen + commentLen
        }

        for name in names where found[name] == nil {
            throw NumpyZipError.entryNotFound(name)
        }
        return found
    }

    private static func readLocalEntry(
        in data: Data, at offset: Int, uncompressedSize: Int
    ) throws -> Data {
        let localSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        guard data[offset..<offset + 4].elementsEqual(localSignature) else {
            throw NumpyZipError.notAZip
        }
        let nameLen = Int(data[offset + 26]) | (Int(data[offset + 27]) << 8)
        let extraLen = Int(data[offset + 28]) | (Int(data[offset + 29]) << 8)
        let payloadStart = offset + 30 + nameLen + extraLen
        let payloadEnd = payloadStart + uncompressedSize
        guard payloadEnd <= data.endIndex else { throw NumpyZipError.notAZip }
        return data.subdata(in: payloadStart..<payloadEnd)
    }
}

enum NumpyZipError: Error {
    case notAZip
    case entryNotFound(String)
    case compressedEntry(String)
}

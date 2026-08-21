//
//  NumpyHeader.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// the .npy format's self-describing prologue: magic, version, then a python-dict-literal
// header naming the array's dtype, shape and memory order. parses just the three fields the
// loader needs - not a general python literal parser
struct NumpyHeader {
    let dtype: String
    let shape: [Int]
    let dataOffset: Int

    static func parse(_ data: Data) throws -> NumpyHeader {
        guard data.count >= 10 else { throw NumpyHeaderError.badMagic }
        let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]
        guard data.prefix(6).elementsEqual(magic) else { throw NumpyHeaderError.badMagic }

        let major = data[data.startIndex + 6]
        let headerLen: Int
        let prologueSize: Int
        switch major {
        case 1:
            headerLen = Int(data[data.startIndex + 8]) | (Int(data[data.startIndex + 9]) << 8)
            prologueSize = 10
        case 2, 3:
            headerLen =
                Int(data[data.startIndex + 8])
                | (Int(data[data.startIndex + 9]) << 8)
                | (Int(data[data.startIndex + 10]) << 16)
                | (Int(data[data.startIndex + 11]) << 24)
            prologueSize = 12
        default:
            throw NumpyHeaderError.unsupportedVersion(major, data[data.startIndex + 7])
        }

        let headerStart = data.startIndex + prologueSize
        let headerEnd = headerStart + headerLen
        guard headerEnd <= data.endIndex else {
            throw NumpyHeaderError.malformedHeader("header length runs past the file")
        }
        guard let header = String(data: data[headerStart..<headerEnd], encoding: .ascii) else {
            throw NumpyHeaderError.malformedHeader("header is not ascii")
        }

        guard let descrMatch = header.firstMatch(of: /'descr':\s*'([^']+)'/) else {
            throw NumpyHeaderError.malformedHeader("no descr field")
        }
        let rawDescr = String(descrMatch.1)
        let dtype =
            rawDescr.first.map { "<>|=".contains($0) ? String(rawDescr.dropFirst()) : rawDescr }
            ?? rawDescr

        guard let orderMatch = header.firstMatch(of: /'fortran_order':\s*(True|False)/) else {
            throw NumpyHeaderError.malformedHeader("no fortran_order field")
        }
        guard orderMatch.1 == "False" else {
            throw NumpyHeaderError.malformedHeader("fortran-ordered array not supported")
        }

        guard let shapeMatch = header.firstMatch(of: /'shape':\s*\(([^)]*)\)/) else {
            throw NumpyHeaderError.malformedHeader("no shape field")
        }
        let shapeText = String(shapeMatch.1).trimmingCharacters(in: .whitespaces)
        let shape: [Int]
        if shapeText.isEmpty {
            shape = []
        } else {
            shape = try shapeText.split(separator: ",").map { piece in
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let value = Int(trimmed) else {
                    throw NumpyHeaderError.malformedHeader(
                        "shape entry '\(trimmed)' is not an integer")
                }
                return value
            }
        }

        return NumpyHeader(dtype: dtype, shape: shape, dataOffset: headerEnd - data.startIndex)
    }
}

enum NumpyHeaderError: Error {
    case badMagic
    case unsupportedVersion(UInt8, UInt8)
    case malformedHeader(String)
}

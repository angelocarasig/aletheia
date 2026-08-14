//
//  CatalogMetadata.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// the display half of the bundle: cover, authors, artists, synopsis, publication
// status. derived from the catalogue rather than the fitted model, so it feeds no
// arithmetic and a build without it still scores
struct CatalogMetadata: Sendable {
    // a sized cover is the imgproxy form of the raw url - the raw one points at
    // whichever upstream served it (anilist, mangaupdates, an anime-planet proxy,
    // myanimelist, kitsu), so there is nothing common to exploit but the encoding
    //
    // urlsafe base64 with padding stripped. verified against all 296,882 rows
    // carrying both forms, of which 8,515 discriminate between the urlsafe and
    // standard alphabets - urlsafe wins every one, so the choice is not cosmetic
    private static let imgproxy = "https://cdn.mangabaka.dev/imgproxy/plain/"

    private let coverOffsets: MappedArray<UInt32>
    private let coverBlob: Data
    private let synopsisOffsets: MappedArray<UInt32>
    private let synopsisBlob: Data
    private let statuses: MappedArray<UInt8>
    private let nameOffsets: MappedArray<UInt32>
    private let nameBlob: Data
    private let authorPtr: MappedArray<UInt32>
    private let authorIdx: MappedArray<UInt32>
    private let artistPtr: MappedArray<UInt32>
    private let artistIdx: MappedArray<UInt32>

    init?(bundle: ModelBundle) {
        guard bundle.metadata != nil else { return nil }
        do {
            coverOffsets = try bundle.array("meta-covers.bin", "offsets", of: UInt32.self)
            coverBlob = try bundle.blob("meta-covers.blob")
            synopsisOffsets = try bundle.array("meta-synopsis.bin", "offsets", of: UInt32.self)
            synopsisBlob = try bundle.blob("meta-synopsis.blob")
            statuses = try bundle.array("meta-status.bin", "statusIndex", of: UInt8.self)
            nameOffsets = try bundle.array("meta-people.bin", "nameOffsets", of: UInt32.self)
            nameBlob = try bundle.blob("meta-people.blob")
            authorPtr = try bundle.array("meta-people.bin", "authorPtr", of: UInt32.self)
            authorIdx = try bundle.array("meta-people.bin", "authorIdx", of: UInt32.self)
            artistPtr = try bundle.array("meta-people.bin", "artistPtr", of: UInt32.self)
            artistIdx = try bundle.array("meta-people.bin", "artistIdx", of: UInt32.self)
        } catch {
            return nil
        }
    }

    func cover(_ row: Int, preset: String = "x250@2") -> URL? {
        guard let raw = span(coverBlob, coverOffsets, row), !raw.isEmpty else { return nil }
        let encoded = Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "\(Self.imgproxy)\(preset)/\(encoded)")
    }

    func synopsis(_ row: Int) -> String? {
        let text = span(synopsisBlob, synopsisOffsets, row)
        return (text?.isEmpty ?? true) ? nil : text
    }

    func status(_ row: Int) -> CatalogStatus {
        CatalogStatus(rawValue: Int(statuses[row])) ?? .unknown
    }

    func authors(_ row: Int) -> [String] { people(row, authorPtr, authorIdx) }
    func artists(_ row: Int) -> [String] { people(row, artistPtr, artistIdx) }

    // one pool shared by both, because the same person is usually both and names
    // repeat heavily - 135,744 distinct names across 302,894 rows
    private func people(_ row: Int,
                        _ pointers: MappedArray<UInt32>,
                        _ indexes: MappedArray<UInt32>) -> [String] {
        pointers.withUnsafeBufferPointer { ptr in
            guard row + 1 < ptr.count else { return [] }
            let lo = Int(ptr[row]), hi = Int(ptr[row + 1])
            guard hi > lo else { return [] }
            return indexes.withUnsafeBufferPointer { idx in
                (lo..<hi).compactMap { span(nameBlob, nameOffsets, Int(idx[$0])) }
            }
        }
    }

    private func span(_ blob: Data, _ offsets: MappedArray<UInt32>, _ index: Int) -> String? {
        offsets.withUnsafeBufferPointer { off in
            guard index + 1 < off.count else { return nil }
            let lo = Int(off[index]), hi = Int(off[index + 1])
            guard hi >= lo, hi <= blob.count else { return nil }
            return String(data: blob[lo..<hi], encoding: .utf8)
        }
    }
}

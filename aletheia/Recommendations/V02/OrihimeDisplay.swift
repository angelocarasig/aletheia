//
//  OrihimeDisplay.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// the display half of the pack, independent of v01's - Orihime carries its own
// title/cover/synopsis/people/status rather than joining against v01's metadata
// by catalogId, confirmed as the intended shape rather than assumed
struct OrihimeDisplay: Sendable {
    private let titleOffsets: MappedArray<UInt32>
    private let titleBlob: Data
    private let coverOffsets: MappedArray<UInt32>
    private let coverBlob: Data
    private let synopsisOffsets: MappedArray<UInt32>
    private let synopsisBlob: Data
    private let statuses: MappedArray<UInt8>
    private let statusNames: [String]
    private let nameOffsets: MappedArray<UInt32>
    private let nameBlob: Data
    private let authorPtr: MappedArray<UInt32>
    private let authorIdx: MappedArray<Int32>
    private let artistPtr: MappedArray<UInt32>
    private let artistIdx: MappedArray<Int32>

    init?(bundle: OrihimeBundle) {
        guard let display = bundle.display else { return nil }
        do {
            titleOffsets = try bundle.array("display/titles_offsets.npy", of: UInt32.self)
            titleBlob = try bundle.blob("display/titles.blob")
            coverOffsets = try bundle.array("display/covers_offsets.npy", of: UInt32.self)
            coverBlob = try bundle.blob("display/covers.blob")
            synopsisOffsets = try bundle.array("display/synopsis_offsets.npy", of: UInt32.self)
            synopsisBlob = try bundle.blob("display/synopsis.blob")
            statuses = try bundle.array("display/status.npy", of: UInt8.self)
            statusNames = display.statuses
            nameOffsets = try bundle.array("display/names_offsets.npy", of: UInt32.self)
            nameBlob = try bundle.blob("display/names.blob")
            authorPtr = try bundle.array("display/author_row_offsets.npy", of: UInt32.self)
            authorIdx = try bundle.array("display/author_name_ids.npy", of: Int32.self)
            artistPtr = try bundle.array("display/artist_row_offsets.npy", of: UInt32.self)
            artistIdx = try bundle.array("display/artist_name_ids.npy", of: Int32.self)
        } catch {
            return nil
        }
    }

    func title(_ row: Int) -> String? { span(titleBlob, titleOffsets, row) }

    // already a complete, ready-to-use url (x250@2 imgproxy preset when the
    // catalogue carries one, else the raw upstream url) per display/metadata.json's
    // own note - no imgproxy re-encoding needed here unlike v01's cover(_:)
    func cover(_ row: Int) -> URL? {
        guard let raw = span(coverBlob, coverOffsets, row), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    func synopsis(_ row: Int) -> String? { span(synopsisBlob, synopsisOffsets, row) }

    func status(_ row: Int) -> CatalogStatus {
        let index = Int(statuses[row])
        guard index < statusNames.count else { return .unknown }
        switch statusNames[index] {
        case "releasing": return .releasing
        case "completed": return .completed
        case "hiatus": return .hiatus
        case "cancelled": return .cancelled
        case "upcoming": return .upcoming
        default: return .unknown
        }
    }

    func authors(_ row: Int) -> [String] { people(row, authorPtr, authorIdx) }
    func artists(_ row: Int) -> [String] { people(row, artistPtr, artistIdx) }

    private func people(
        _ row: Int,
        _ pointers: MappedArray<UInt32>,
        _ indexes: MappedArray<Int32>
    ) -> [String] {
        pointers.withUnsafeBufferPointer { ptr in
            guard row + 1 < ptr.count else { return [] }
            let lo = Int(ptr[row])
            let hi = Int(ptr[row + 1])
            guard hi > lo else { return [] }
            return indexes.withUnsafeBufferPointer { idx in
                (lo..<hi).compactMap { span(nameBlob, nameOffsets, Int(idx[$0])) }
            }
        }
    }

    private func span(_ blob: Data, _ offsets: MappedArray<UInt32>, _ index: Int) -> String? {
        offsets.withUnsafeBufferPointer { off in
            guard index + 1 < off.count else { return nil }
            let lo = Int(off[index])
            let hi = Int(off[index + 1])
            guard hi >= lo, hi <= blob.count else { return nil }
            return String(data: blob[lo..<hi], encoding: .utf8)
        }
    }
}

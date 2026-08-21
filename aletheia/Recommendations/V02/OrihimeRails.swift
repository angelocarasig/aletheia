//
//  OrihimeRails.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

struct OrihimeCandidate: Sendable {
    let row: Int
    let catalogId: Int64
    let score: Float
}

// the resolved path: a catalogue row with a precomputed rail answers from
// rails/rows.npy + scores.npy directly, no scoring on-device. about half the
// catalogue (153,584 of 302,894) has one - the rest fall through to nil, which
// the (unbuilt) live-compute phase is what handles, not this type
struct OrihimeRails: Sendable {
    private let titles: MappedArray<Int64>
    private let seedRows: MappedArray<Int32>
    private let rows: MappedArray<Int32>
    private let scores: MappedArray<Float16>
    private let rating: MappedArray<UInt8>
    private let type: MappedArray<UInt8>
    private let register: MappedArray<UInt8>
    private let excluded: MappedArray<UInt8>
    private let year: MappedArray<Int16>
    private let formatByIndex: [Int: CatalogFormat]
    private let k: Int

    // -32768, per V02Artifact.md - a year of "unknown" rather than a missing row
    private static let yearUnknown: Int16 = -32768

    init(bundle: OrihimeBundle) throws {
        titles = try bundle.array("titles.npy", of: Int64.self)
        seedRows = try bundle.array("rails/seed_rows.npy", of: Int32.self)
        rows = try bundle.array("rails/rows.npy", of: Int32.self)
        scores = try bundle.array("rails/scores.npy", of: Float16.self)
        rating = try bundle.array("rating.npy", of: UInt8.self)
        type = try bundle.array("type.npy", of: UInt8.self)
        register = try bundle.array("register.npy", of: UInt8.self)
        excluded = try bundle.array("excluded.npy", of: UInt8.self)
        year = try bundle.array("year.npy", of: Int16.self)
        k = bundle.manifest.counts.k

        // type.npy's index into manifest.typeCodes does not match CatalogFormat's
        // own raw values (confirmed: manhua/manhwa and novel/oel are swapped) -
        // mapping by name is the only correct join, an index cast would silently
        // mislabel a fifth of the catalogue's formats
        let byName: [String: CatalogFormat] = [
            "manga": .manga, "manhwa": .manhwa, "manhua": .manhua,
            "oel": .oel, "novel": .novel, "other": .other,
        ]
        var map: [Int: CatalogFormat] = [:]
        for (index, name) in bundle.manifest.typeCodes.enumerated() {
            map[index] = byName[name]
        }
        formatByIndex = map
    }

    // binary search - titles.npy is sorted ascending by catalogId, confirmed
    // directly against the real pack, not assumed
    func row(forCatalogId catalogId: Int64) -> Int? {
        titles.withUnsafeBufferPointer { values in
            var low = 0
            var high = values.count - 1
            while low <= high {
                let mid = (low + high) / 2
                if values[mid] == catalogId { return mid }
                if values[mid] < catalogId { low = mid + 1 } else { high = mid - 1 }
            }
            return nil
        }
    }

    private func seedIndex(forRow row: Int) -> Int? {
        seedRows.withUnsafeBufferPointer { values in
            var low = 0
            var high = values.count - 1
            let target = Int32(row)
            while low <= high {
                let mid = (low + high) / 2
                if values[mid] == target { return mid }
                if values[mid] < target { low = mid + 1 } else { high = mid - 1 }
            }
            return nil
        }
    }

    func candidates(
        forRow row: Int, ceiling: ContentCeiling, formats: Set<CatalogFormat>, limit: Int
    ) -> [OrihimeCandidate]? {
        guard let seed = seedIndex(forRow: row) else { return nil }
        let seedRegister = register[row]
        var results: [OrihimeCandidate] = []
        results.reserveCapacity(min(limit, k))

        for i in 0..<k {
            guard results.count < limit else { break }
            let candidateRow = Int(rows[seed * k + i])
            guard excluded[candidateRow] == 0 else { continue }
            guard rating[candidateRow] <= UInt8(ceiling.rawValue) else { continue }
            guard register[candidateRow] == seedRegister else { continue }
            guard let format = formatByIndex[Int(type[candidateRow])], formats.contains(format)
            else { continue }
            results.append(
                OrihimeCandidate(
                    row: candidateRow,
                    catalogId: titles[candidateRow],
                    score: Float(scores[seed * k + i])))
        }
        return results
    }

    // presentation accessors, for a row already known to be a candidate (or the
    // seed itself) - not filters, just the same per-row arrays candidates() reads
    func format(forRow row: Int) -> CatalogFormat? { formatByIndex[Int(type[row])] }
    func register(forRow row: Int) -> RegisterAxis { RegisterAxis(rawValue: Int(register[row])) ?? .general }
    func classification(forRow row: Int) -> Classification {
        ContentCeiling(rawValue: Int(rating[row]))?.classification ?? .Unknown
    }
    func year(forRow row: Int) -> Int? {
        let value = year[row]
        return value == Self.yearUnknown ? nil : Int(value)
    }
}

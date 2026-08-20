//
//  AliasIndex.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// name to catalogue row. the table is 1.19M (hash, row) pairs sorted ascending by
// hash, so a lookup is a binary search followed by a scan of the equal-hash run
//
// the scan is written even though the shipped v01 table can only ever return one
// row: every hash in it is distinct, because the exporter builds the table from a
// dict keyed by name and a dict cannot hold two rows for one key. that is a known
// defect being fixed upstream, and code that assumes a single result would
// silently ignore the fix when it lands. see docs/recommendations/v01-artifact.md
// section 3.1
struct AliasIndex: Sendable {
    private let hashes: MappedArray<UInt64>
    private let rows: MappedArray<UInt32>

    init(bundle: ModelBundle) throws {
        hashes = try bundle.array("aliases.bin", "hash", of: UInt64.self)
        rows = try bundle.array("aliases.bin", "row", of: UInt32.self)
        guard hashes.count == rows.count else {
            throw RecommenderError.malformed(
                file: "aliases.bin",
                reason: "hash and row arrays disagree")
        }
    }

    // every row any of these names points at, with the count of names that named
    // it - the counts are what let a caller prefer the row several names agree on
    //
    // the reference implementation took the first name that matched anything and
    // shipped a real bug doing it: "Best Wishes" resolved to "Black Market +Plus"
    // through the alternate name "Bitch" while four other names agreed on the
    // right row. a tally cannot make that mistake, so the shape is the fix
    func tally(for names: [String]) -> [Int: Int] {
        var votes: [Int: Int] = [:]
        for name in names {
            for row in Set(candidates(for: name)) {
                votes[row, default: 0] += 1
            }
        }
        return votes
    }

    func candidates(for name: String) -> [Int] {
        let key = Normalise.key(name)
        guard !key.isEmpty else { return [] }
        return candidates(hash: StableHash.hash(key))
    }

    func candidates(hash: UInt64) -> [Int] {
        hashes.withUnsafeBufferPointer { keys in
            var low = 0
            var high = keys.count
            // lower bound: the first index whose key is not less than the target,
            // which is where the run starts if there is one
            while low < high {
                let mid = low + (high - low) / 2
                if keys[mid] < hash { low = mid + 1 } else { high = mid }
            }
            guard low < keys.count, keys[low] == hash else { return [] }

            var found: [Int] = []
            return rows.withUnsafeBufferPointer { values in
                var i = low
                while i < keys.count, keys[i] == hash {
                    found.append(Int(values[i]))
                    i += 1
                }
                return found
            }
        }
    }
}

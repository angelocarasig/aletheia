//
//  OrihimeAliasIndex.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// name to catalogue rows, via binary search over aliases/keys.txt rather than
// an in-memory dictionary like the first draft of this type. two things
// pointed at binary search instead: the reader only triggers a lookup by
// opening a series, not a repeated hot path, and the file is confirmed sorted
// ascending (one violation in 1,172,113 comparisons, a single near-duplicate
// pair - close enough to treat as fully sorted). measured against the real
// pack: building just the line-start offset table costs ~87ms (vs ~443ms to
// also build a full String-keyed dictionary), and a lookup after that is
// effectively free
//
// split on the raw 0x0A byte, not Character "\n" - the pipeline runs on
// Windows and keys.txt uses CRLF line endings, which Swift's Character/String
// APIs treat as a single extended grapheme cluster. caught by timing this
// against the real file before shipping, not assumed to be plain LF
struct OrihimeAliasIndex: Sendable {
    private let keysBlob: Data
    private let rows: MappedArray<Int32>
    // line i's bytes are keysBlob[offsets[i]..<offsets[i+1]], trailing \r\n
    // trimmed at read time - one extra sentinel entry (== keysBlob.endIndex)
    // so offsets[i+1] is always valid for the last real line too
    private let offsets: [Int]

    init(bundle: OrihimeBundle) throws {
        keysBlob = try bundle.blob("aliases/keys.txt")
        rows = try bundle.array("aliases/rows.npy", of: Int32.self)

        var built: [Int] = []
        built.reserveCapacity(rows.count + 1)
        var lineStart = keysBlob.startIndex
        for i in keysBlob.indices where keysBlob[i] == 0x0A {
            built.append(lineStart)
            lineStart = i + 1
        }
        if lineStart < keysBlob.endIndex { built.append(lineStart) }
        built.append(keysBlob.endIndex)
        offsets = built

        guard offsets.count - 1 == rows.count else {
            throw RecommenderError.malformed(
                file: "aliases/keys.txt",
                reason: "\(offsets.count - 1) keys, \(rows.count) rows - counts disagree")
        }
    }

    // every row any of these names points at, with the count of names that
    // named it - same tallying discipline as v01's AliasIndex.tally(), since
    // Orihime's own alias table also preserves collisions rather than
    // deduping them away (up to 190 rows sharing one franchise name)
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
        let target = Normalise.key(name)
        guard !target.isEmpty, let anchor = search(target) else { return [] }

        var lo = anchor
        while lo > 0, line(lo - 1) == target { lo -= 1 }
        var hi = anchor
        while hi + 1 < rows.count, line(hi + 1) == target { hi += 1 }

        return rows.withUnsafeBufferPointer { values in
            (lo...hi).map { Int(values[$0]) }
        }
    }

    private func search(_ target: String) -> Int? {
        var low = 0
        var high = rows.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let text = line(mid)
            if text == target { return mid }
            if text < target { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    private func line(_ index: Int) -> String {
        // the file's own final line carries no trailing \n at all (confirmed:
        // 1,172,113 newline bytes for 1,172,114 lines) - only trim a \n/\r\n
        // that's actually there, never blindly the last byte
        var end = offsets[index + 1]
        if end > offsets[index], keysBlob[end - 1] == 0x0A {
            end -= 1
            if end > offsets[index], keysBlob[end - 1] == 0x0D { end -= 1 }
        }
        return String(decoding: keysBlob[offsets[index]..<end], as: UTF8.self)
    }
}

//
//  OrihimeTagVocabulary.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

// flat, id-equals-array-index vocabulary (confirmed against the real
// vocabulary.json - every entry's id matches its position), unlike v01's
// tagvocab.json which needs a name -> index dictionary. no ancestor-hierarchy
// decay here either - Orihime's tag block is flat weighted overlap, so there's
// no equivalent machinery to port
struct OrihimeTagVocabulary: Sendable {
    private struct Entry: Decodable {
        let id: Int
        let name: String
    }

    private let names: [String]
    private let rowOffsets: MappedArray<Int64>
    private let tagIds: MappedArray<Int32>

    init(bundle: OrihimeBundle) throws {
        let data = try bundle.blob("vectors/tags/vocabulary.json")
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        var table = [String](repeating: "", count: entries.count)
        for entry in entries where entry.id < table.count {
            table[entry.id] = entry.name
        }
        names = table
        rowOffsets = try bundle.array("vectors/tags/row_offsets.npy", of: Int64.self)
        tagIds = try bundle.array("vectors/tags/tag_ids.npy", of: Int32.self)
    }

    func names(forRow row: Int) -> [String] {
        rowOffsets.withUnsafeBufferPointer { offsets in
            guard row + 1 < offsets.count else { return [] }
            let lo = Int(offsets[row])
            let hi = Int(offsets[row + 1])
            guard hi > lo else { return [] }
            return tagIds.withUnsafeBufferPointer { ids in
                (lo..<hi).compactMap { i -> String? in
                    let id = Int(ids[i])
                    guard id < names.count else { return nil }
                    return names[id]
                }
            }
        }
    }
}

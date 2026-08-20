//
//  MappedArray.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// a window onto mapped bytes. it holds the Data rather than a pointer, so the
// mapping outlives every use and nothing escapes a withUnsafeBytes closure -
// which is the one way to read this safely, however tempting the alternative
// looks in a hot loop
struct MappedArray<Element>: Sendable {
    private let data: Data
    private let offset: Int
    let count: Int

    init(data: Data, offset: Int, count: Int) {
        self.data = data
        self.offset = offset
        self.count = count
    }

    func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows
        -> R
    {
        try data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: offset)
            return try body(
                UnsafeBufferPointer(
                    start: base.assumingMemoryBound(to: Element.self),
                    count: count))
        }
    }

    subscript(index: Int) -> Element {
        withUnsafeBufferPointer { $0[index] }
    }
}

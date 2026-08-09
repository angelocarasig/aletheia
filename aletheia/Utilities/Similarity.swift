//
//  Similarity.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

// how alike two titles are, 0...1. titles arrive from sources rather than
// keyboards, so the noise is subtitle tails, word order and punctuation - not
// typos. token-set scoring absorbs those; levenshtein covers near-identical
// spellings. the max of the two is taken so each covers the other's blind spot
enum Similarity {
    static func score(_ a: String, _ b: String) -> Double {
        let left = normalize(a)
        let right = normalize(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        guard left != right else { return 1 }
        return max(levenshtein(left, right), min(tokenSet(left, right), tokenSetCeiling))
    }

    // a subset title ("solo leveling" inside "solo leveling ragnarok") scores a
    // perfect token-set ratio. capped so 100% is reserved for titles that are
    // actually equal after normalization - a claim, not a resemblance
    private static let tokenSetCeiling = 0.95

    // lowercased, diacritics folded, punctuation collapsed - so "Solo Leveling!"
    // and "solo leveling" measure as the same string
    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let collapsed = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return collapsed.split(separator: " ").joined(separator: " ")
    }

    private static func levenshtein(_ a: String, _ b: String) -> Double {
        let x = Array(a)
        let y = Array(b)

        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)

        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let substitution = previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }

        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    // fuzzywuzzy's token_set_ratio: the shared words score against each side's
    // remainder, so a title that is a subset of a longer one still scores ~1.
    // deliberate over-match - candidates are ranked for a human to confirm,
    // never auto-merged
    private static func tokenSet(_ a: String, _ b: String) -> Double {
        let ta = Set(a.split(separator: " "))
        let tb = Set(b.split(separator: " "))

        let shared = ta.intersection(tb).sorted().joined(separator: " ")
        guard !shared.isEmpty else { return 0 }

        let onlyA = ta.subtracting(tb).sorted().joined(separator: " ")
        let onlyB = tb.subtracting(ta).sorted().joined(separator: " ")

        let combinedA = onlyA.isEmpty ? shared : shared + " " + onlyA
        let combinedB = onlyB.isEmpty ? shared : shared + " " + onlyB

        return max(
            levenshtein(shared, combinedA),
            levenshtein(shared, combinedB),
            levenshtein(combinedA, combinedB)
        )
    }
}

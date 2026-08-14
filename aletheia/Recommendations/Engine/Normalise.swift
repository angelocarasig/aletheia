//
//  Normalise.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// the key a title is looked up by. every name in the catalogue was hashed
// through the python equivalent of this at export time, so any divergence here
// does not throw - the lookup simply misses, and the resolution rate erodes in a
// way nothing reports
//
// the traps this has to survive, all real fixture cases:
//
//   Straße           -> strasse      lowercased() gives straße, which is wrong
//   İstanbul         -> istanbul
//   ὉΔΟΣ             -> οδοσ
//   Shōnen           -> shonen       the macron is a combining mark after NFKD
//   ＦＵＬＬＷＩＤＴＨ -> fullwidth     compatibility decomposition, not canonical
//   ǅ digraph        -> dz digraph   full case folding, not simple
//   ①②③              -> 123
//
// Foundation's .caseInsensitive folding is FULL case folding, which is what
// python's str.casefold() does and what .lowercased() does not - verified
// against all 3017 pairs in the export's fixtures
enum Normalise {
    static func key(_ value: String) -> String {
        // NFKD rather than NFD: compatibility decomposition is what turns
        // fullwidth forms, ligatures and circled digits into their plain
        // equivalents, and the catalogue is full of all three
        let decomposed = value.decomposedStringWithCompatibilityMapping

        // combining class rather than a category test - this is exactly what
        // python's unicodedata.combining(c) reports, and it is what separates a
        // macron from the letter it sits on
        let stripped = String(String.UnicodeScalarView(
            decomposed.unicodeScalars.filter {
                $0.properties.canonicalCombiningClass == .notReordered
            }))

        let folded = stripped.folding(options: .caseInsensitive, locale: nil)

        // every run of non-word, non-space scalars becomes one space, then runs
        // of space collapse. done in a single pass because the alternative is
        // three passes over a string that is usually shorter than the buffer
        var out = String()
        out.reserveCapacity(folded.utf8.count)
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if isWord(scalar) {
                if pendingSpace, !out.isEmpty { out.unicodeScalars.append(" ") }
                pendingSpace = false
                out.unicodeScalars.append(scalar)
            } else {
                // whitespace and punctuation are the same thing here: a break
                pendingSpace = true
            }
        }
        return out
    }

    // python's \w on a str: letters, digits and underscore, unicode-aware. CJK
    // is alphabetic and therefore survives, which is the whole reason the rule
    // is stated this way rather than as an ascii allowlist
    private static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic
            || scalar.properties.numericType != nil
            || scalar == "_"
    }
}

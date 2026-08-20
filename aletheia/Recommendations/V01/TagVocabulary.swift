//
//  TagVocabulary.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation

// the tag space: 2,729 columns, of which 253 are ancestor columns written under a
// "^" prefix. it is needed for two jobs - turning our own tags into a vector when
// a title does not resolve to a catalogue row, and turning a row's columns back
// into names for display
struct TagVocabulary: Sendable {
    struct Sparse: Sendable {
        let columns: [Int]
        let values: [Float]
    }

    private let column: [String: Int]
    private let name: [String]
    private let aliases: [String: String]

    // built on first use rather than at init. it runs Normalise.key over every
    // vocabulary name and every alias - roughly 2,500 strings, each an NFKD
    // decompose, a combining-class filter, a case fold and a rebuild - and it is
    // read only by encode(), i.e. only on the projected path. a seed that
    // resolved by catalogue id or by alias never touches it, so at launch this
    // was ~12 ms spent on a table most sessions never look at
    //
    // a box rather than a lazy var because TagVocabulary is a Sendable struct:
    // lazy would make encode() mutating and take Sendable with it
    private let canonicalBox = Once<[String: String]>()

    private var canonical: [String: String] {
        canonicalBox.value {
            // an incoming tag arrives however its source spelled it, so the index
            // is keyed by the normalised form. aliases resolve first and are
            // already normalised on the export side - "sci fi" to "Sci-Fi", "bl"
            // to "Boys Love" - so they map straight onto a canonical name
            var lookup: [String: String] = [:]
            for raw in column.keys where !raw.hasPrefix("^") {
                lookup[Normalise.key(raw)] = raw
            }
            for (from, to) in aliases {
                lookup[Normalise.key(from)] = to
            }
            return lookup
        }
    }
    private let ancestors: [String: [String]]
    private let idf: [Float]
    private let weights: [String: Float]
    private let typeWords: [String: String]
    private let decay: Float

    var size: Int { name.count }

    private struct Document: Decodable {
        let vocab: [String: Int]
        let idf: [Float]
        let ancestors: [String: [String]]
        let tagAliases: [String: String]
        let typeWords: [String: String]
        let tagWeights: [String: Float]
    }

    init(bundle: ModelBundle) throws {
        guard let url = Foundation.Bundle.main.url(forResource: "tagvocab", withExtension: "json")
        else {
            throw RecommenderError.malformed(file: "tagvocab.json", reason: "not in the bundle")
        }
        let doc: Document
        do {
            doc = try JSONDecoder().decode(Document.self, from: try Data(contentsOf: url))
        } catch {
            throw RecommenderError.malformed(
                file: "tagvocab.json",
                reason: String(describing: error))
        }
        guard doc.idf.count == doc.vocab.count else {
            throw RecommenderError.malformed(
                file: "tagvocab.json",
                reason: "idf and vocab disagree")
        }

        column = doc.vocab
        var names = [String](repeating: "", count: doc.vocab.count)
        for (raw, index) in doc.vocab where index < names.count { names[index] = raw }
        name = names

        aliases = doc.tagAliases
        ancestors = doc.ancestors
        idf = doc.idf
        weights = doc.tagWeights
        typeWords = doc.typeWords
        decay = bundle.manifest.constants.ancestorDecay
    }

    // the vector a payload's tags produce, directly comparable to any tags.bin
    // row. our own tags carry no strength, so every one enters at 1.0 - which the
    // handover permits and which is precisely what projected mode gives up
    // against a catalogue row that knows defining from incidental
    func encode(_ tags: [String], strengths: [String: String] = [:]) -> Sparse {
        var counts: [Int: Float] = [:]

        for tag in tags {
            guard let raw = canonical[Normalise.key(tag)] else { continue }
            let weight = strengths[tag].flatMap { weights[$0] } ?? 1
            if let index = column[raw] {
                counts[index, default: 0] += weight
            }
            // nearest ancestor first, each one a further step of decay. this was
            // the single largest quality win in the whole model, and it is baked
            // into every stored row - a payload that skipped it would sit in a
            // different space from everything it is compared against
            for (depth, ancestor) in (ancestors[raw] ?? []).enumerated() {
                guard let index = column["^" + ancestor] else { continue }
                counts[index, default: 0] += weight * powf(decay, Float(depth + 1))
            }
        }

        // sublinear scaling then idf, then l2 - the order the export used. a
        // sorted column list is what lets a caller walk it against a CSR row
        var columns = [Int]()
        var values = [Float]()
        var norm: Float = 0
        for index in counts.keys.sorted() {
            let count = counts[index] ?? 0
            guard count > 0 else { continue }
            let value = (1 + logf(count)) * idf[index]
            columns.append(index)
            values.append(value)
            norm += value * value
        }
        if norm > 0 {
            let scale = 1 / norm.squareRoot()
            for i in values.indices { values[i] *= scale }
        }
        return Sparse(columns: columns, values: values)
    }

    // display names for a row's columns, ancestor columns dropped - they are a
    // scoring device and were never anything a reader chose
    func names(for columns: [Int]) -> [String] {
        columns.compactMap { index in
            guard index < name.count else { return nil }
            let raw = name[index]
            return raw.hasPrefix("^") ? nil : raw
        }
    }

    // type hints, which are the only thing typeBoost ever fires on. a title
    // carrying the word "manhwa" says something about its own format, and that is
    // the whole mechanism
    func hints(in text: String) -> Set<String> {
        let key = Normalise.key(text)
        var found: Set<String> = []
        for (word, type) in typeWords where key.contains(Normalise.key(word)) {
            found.insert(type)
        }
        return found
    }
}

// a value computed once, on whichever thread asks first, and shared thereafter.
// @unchecked because the lock is what provides the safety the compiler cannot see
final class Once<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    func value(_ build: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let stored { return stored }
        let made = build()
        stored = made
        return made
    }
}

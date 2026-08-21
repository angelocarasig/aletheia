//
//  ModelBundle+Probe.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

#if DEBUG
    import Foundation
    import Tagged

    // the loader's check. it reads back every array both manifests declare and
    // compares what came out against what the manifest said would - which is exactly
    // the path a Swift port has to walk, deliberately without help from anything
    // above it, so anything undocumented fails here first rather than inside the
    // scorer where a wrong count reads as a wrong recommendation
    //
    // this is a probe, not the wiring. kept deliberately past Composition owning
    // a Recommender - with no test target it is the only regression check for
    // steps 2 through 6 (docs/recommendations/port-plan.md)
    extension ModelBundle {
        private struct GoldenCase: Decodable {
            struct Row: Decodable {
                let row: Int
                let catalogId: Int
                let score: Float
            }
            let seedRow: Int
            let seedTitle: String
            let ceiling: String
            let types: [String]
            let k: Int
            let results: [Row]
        }

        // every seed's top 20, computed from these exact binaries by the exporter. row
        // order has to match exactly because the tie-break is total; scores are
        // asserted to 1e-4 because accumulation order legitimately differs between
        // implementations
        private func rank(against url: URL, log: (String) -> Void) throws {
            let cases = try JSONDecoder().decode([GoldenCase].self, from: try Data(contentsOf: url))
            let scorer = try Scorer(bundle: self)
            let ladder = manifest.ratingLadder
            let allTypes = manifest.types

            var exact = 0
            var wrongOrder = 0
            var drifted = 0
            var worst: Float = 0
            let started = Date()

            for test in cases {
                guard let ceiling = ladder.firstIndex(of: test.ceiling) else { continue }
                let types = Set(test.types.compactMap { allTypes.firstIndex(of: $0) })
                let got = scorer.rank(row: test.seedRow, ceiling: ceiling, types: types, k: test.k)

                let mine = got.ranked.map(\.row)
                let want = test.results.map(\.row)
                guard mine == want else {
                    wrongOrder += 1
                    if wrongOrder <= 3 {
                        let overlap = Set(mine).intersection(want).count
                        let first = Array(zip(mine, want)).firstIndex { $0 != $1 } ?? 0
                        log(
                            "  RANK MISMATCH seed \(test.seedRow) \(test.seedTitle.prefix(30)) "
                                + "overlap \(overlap)/\(want.count), first differs at \(first)")
                    }
                    continue
                }
                let delta =
                    zip(got.ranked, test.results).map { abs($0.score - $1.score) }.max() ?? 0
                worst = max(worst, delta)
                if delta < 1e-4 { exact += 1 } else { drifted += 1 }
            }

            let per = Date().timeIntervalSince(started) / Double(max(cases.count, 1))
            log(
                "ranking - \(exact)/\(cases.count) exact, \(wrongOrder) wrong order, "
                    + "\(drifted) score drift, worst delta \(String(format: "%.2e", worst)), "
                    + String(format: "%.0fms per query", per * 1000))
        }

        // step 7: the whole thing through the protocol, as a caller would use it.
        // proves the wiring, the metadata join and both resolution tiers - the parts
        // no fixture covers because they only exist on this side. "Chainsaw Man" is
        // just a title guaranteed to resolve in either pack's alias table, not
        // anything the log needs to name back - the log stays generic even though
        // the input doesn't, since recommender is `any Recommender` here (whichever
        // pack is active), not necessarily this file's own ModelBundle
        static func probe(_ recommender: Recommender) async {
            let log = { (m: String) in AppLog.shared.log(m, category: "recommender") }
            let descriptor = await recommender.descriptor
            guard descriptor.titleCount > 0 else {
                log("recommender has no model")
                return
            }
            log(
                "recommender \(descriptor.slug) - \(descriptor.titleCount) titles, "
                    + "metadata \(descriptor.hasMetadata ? "yes" : "no"), "
                    + "text encoder \(descriptor.encodesText ? "yes" : "no")")

            do {
                let started = Date()
                let set = try await recommender.recommend(
                    Payload(titles: ["Chainsaw Man"], tags: []),
                    ceiling: .suggestive, formats: CatalogFormat.comics, limit: 5)
                let took = Date().timeIntervalSince(started)

                guard case .resolved(let row, _, let votes) = set.seed else {
                    log("  seed resolved unexpectedly: \(set.seed)")
                    return
                }
                log(
                    String(
                        format: "  resolved probe seed to row %d (%d vote) in %.0fms, wTagEff %.2f",
                        row, votes, took * 1000, set.wTagEff))
                for r in set.results.prefix(3) {
                    log(
                        "    [\(r.catalogId.rawValue)] "
                            + String(format: "score %.2f conf %.2f", r.score, r.confidence)
                            + " - \(r.format) \(r.publication) \(r.year.map(String.init) ?? "?")"
                            + " - cover \(r.cover == nil ? "none" : "yes")"
                            + " - synopsis \(r.synopsis?.count ?? 0) chars")
                }

                let projected = try await recommender.recommend(
                    Payload(
                        titles: ["zzzz no such series zzzz"],
                        tags: ["Action", "Time Travel", "Revenge"]),
                    ceiling: .suggestive, formats: CatalogFormat.comics, limit: 3)
                if case .projected(let encoded, let dropped) = projected.seed {
                    log(
                        "  projected - \(encoded) columns encoded, \(dropped) tags dropped, "
                            + "\(projected.results.count) results")
                } else {
                    log("  projected path did not project: \(projected.seed)")
                }
            } catch {
                AppLog.shared.log(
                    "recommend FAILED - \(error)", level: .error, category: "recommender")
            }
        }

        static func probe() {
            let log = { (m: String) in AppLog.shared.log(m, category: "recommender") }
            do {
                let t0 = Date()
                let bundle = try ModelBundle.load(from: .appBundle())
                let mapped = Date().timeIntervalSince(t0)
                let n = bundle.titleCount

                let indptr = try bundle.array("tags.bin", "indptr", of: UInt32.self)
                let indices = try bundle.array("tags.bin", "indices", of: UInt16.self)
                let values = try bundle.array("tags.bin", "values", of: UInt8.self)
                let ids = try bundle.array("ids.bin", "catalogId", of: Int32.self)
                let year = try bundle.array("meta.bin", "year", of: Int16.self)
                let flags = try bundle.array("meta.bin", "flags", of: UInt8.self)
                let hasEmbed = try bundle.array("has_embed.bin", "hasEmbedding", of: UInt8.self)
                let embeddings = try bundle.array("embeddings.bin", "values", of: Int8.self)
                let aliasHash = try bundle.array("aliases.bin", "hash", of: UInt64.self)
                let aliasRow = try bundle.array("aliases.bin", "row", of: UInt32.self)
                let titleOff = try bundle.array("titles.bin", "offsets", of: UInt32.self)
                let titles = try bundle.blob("titles.blob")

                var problems: [String] = []
                func expect(_ ok: Bool, _ what: String) {
                    if !ok { problems.append(what) }
                }
                expect(indptr.count == n + 1, "indptr \(indptr.count) != n+1")
                expect(indices.count == values.count, "indices/values disagree")
                expect(ids.count == n, "ids \(ids.count)")
                expect(year.count == n && flags.count == n, "meta arrays")
                expect(hasEmbed.count == n, "has_embed \(hasEmbed.count)")
                expect(aliasHash.count == aliasRow.count, "alias arrays disagree")
                expect(titleOff.count == n + 1, "title offsets \(titleOff.count)")

                // the structural invariants, which a correct length cannot prove:
                // CSR bounds have to close on nnz, and the title blob has to end
                // exactly where its last offset says
                expect(Int(indptr[n]) == indices.count, "indptr[n] != nnz")
                expect(Int(titleOff[n]) == titles.count, "title blob length")
                expect(aliasHash[0] <= aliasHash[aliasHash.count - 1], "aliases not ascending")

                if let dims = bundle.manifest.files["embeddings.bin"]?.dims {
                    expect(embeddings.count == n * dims, "embeddings \(embeddings.count)")
                }

                // one real read, so this proves bytes rather than bookkeeping
                let first =
                    String(
                        data: titles[Int(titleOff[0])..<Int(titleOff[1])],
                        encoding: .utf8) ?? "?"

                log(
                    "model v\(bundle.manifest.formatVersion) mapped in "
                        + String(format: "%.0fms", mapped * 1000)
                        + " - \(n) rows, \(indices.count) tag nnz, \(aliasHash.count) aliases"
                        + ", row 0 is \(ids[0]) \"\(first)\"")

                if let pack = bundle.metadata {
                    let covers = try bundle.array("meta-covers.bin", "offsets", of: UInt32.self)
                    let status = try bundle.array("meta-status.bin", "statusIndex", of: UInt8.self)
                    let synopsis = try bundle.array("meta-synopsis.bin", "offsets", of: UInt32.self)
                    let people = try bundle.array("meta-people.bin", "authorPtr", of: UInt32.self)
                    expect(covers.count == n + 1 && synopsis.count == n + 1, "pack offsets")
                    expect(status.count == n, "status \(status.count)")
                    expect(people.count == n + 1, "authorPtr \(people.count)")
                    expect(
                        Int(synopsis[n]) == (try bundle.blob("meta-synopsis.blob")).count,
                        "synopsis blob length")
                    log(
                        "metadata v\(pack.metadataVersion) - \(pack.statuses.count) statuses, "
                            + "\(Int(synopsis[n]) / 1_000_000) MB of synopsis")
                } else {
                    log("no metadata pack in this build")
                }

                // the 3517 fixtures were run against these same two files on macOS,
                // which assumes iOS folds identically. one trap case proves it here -
                // lowercased() would give "straße" and every alias lookup would miss
                let folded = Normalise.key("Straße")
                expect(folded == "strasse", "casefold on device gave \(folded)")
                expect(
                    StableHash.hash("strasse") == 2_708_255_948_388_058_996, "fnv1a64 on device")

                // step 4: resolve a sample of catalogue titles by their own primary
                // name. the ceiling is a property of the shipped table rather than of
                // this code - 9.5% of rows are reachable only as some other series,
                // measured against the whole catalogue in python before any of this
                // was written, so anything near 90% here means the lookup agrees
                let index = try AliasIndex(bundle: bundle)
                let step = max(1, n / 2000)
                var probed = 0
                var hit = 0
                var elsewhere = 0
                var absent = 0
                var multi = 0
                let started = Date()
                for row in stride(from: 0, to: n, by: step) {
                    let title =
                        String(
                            data: titles[Int(titleOff[row])..<Int(titleOff[row + 1])],
                            encoding: .utf8) ?? ""
                    guard !title.isEmpty else { continue }
                    probed += 1
                    let found = index.candidates(for: title)
                    if found.count > 1 { multi += 1 }
                    if found.isEmpty {
                        absent += 1
                    } else if found.contains(row) {
                        hit += 1
                    } else {
                        elsewhere += 1
                    }
                }
                let per = Date().timeIntervalSince(started) / Double(max(probed, 1))
                log(
                    "alias lookup - \(probed) titles, "
                        + "\(100 * hit / max(probed, 1))% resolve to themselves, "
                        + "\(elsewhere) to another row, \(absent) absent, \(multi) ambiguous, "
                        + String(format: "%.1fus each", per * 1_000_000))

                // step 6: take a row's own tags back out as names, re-encode them,
                // and see how close the result lands to the stored vector. it cannot
                // be exact - the catalogue weighted its tags defining/core/recurrent
                // and ours arrive flat - so the gap IS the measurement of what
                // projected mode gives up
                let vocabStarted = Date()
                let vocabulary = try TagVocabulary(bundle: bundle)
                let vocabTook = Date().timeIntervalSince(vocabStarted)
                let idsStarted = Date()
                let ascending = ids.withUnsafeBufferPointer { values -> Bool in
                    for i in 1..<values.count where values[i] < values[i - 1] { return false }
                    return true
                }
                let idsTook = Date().timeIntervalSince(idsStarted)
                log(
                    String(
                        format:
                            "cold cost - map %.0fms, vocabulary %.0fms, ids scan %.0fms (ascending %@)",
                        mapped * 1000, vocabTook * 1000, idsTook * 1000, ascending ? "yes" : "no"))
                var cosines: [Float] = []
                let tagScale = Float(bundle.manifest.files["tags.bin"]?.valueScale ?? 0)
                for row in stride(from: 0, to: n, by: max(1, n / 300)) {
                    let lo = Int(indptr[row])
                    let hi = Int(indptr[row + 1])
                    guard hi - lo >= 5 else { continue }
                    var columns: [Int] = []
                    var stored: [Int: Float] = [:]
                    for i in lo..<hi {
                        columns.append(Int(indices[i]))
                        stored[Int(indices[i])] = Float(values[i]) * tagScale
                    }
                    let encoded = vocabulary.encode(vocabulary.names(for: columns))
                    guard !encoded.columns.isEmpty else { continue }
                    var dot: Float = 0
                    for (i, column) in encoded.columns.enumerated() {
                        dot += encoded.values[i] * (stored[column] ?? 0)
                    }
                    cosines.append(dot)
                }
                if !cosines.isEmpty {
                    let mean = cosines.reduce(0, +) / Float(cosines.count)
                    log(
                        "payload encoder - \(cosines.count) rows re-encoded, "
                            + String(
                                format: "cosine mean %.3f min %.3f max %.3f",
                                mean, cosines.min() ?? 0, cosines.max() ?? 0)
                            + ", vocabulary \(vocabulary.size) columns")
                    expect(mean > 0.8, "re-encoded rows diverge from stored (mean \(mean))")
                }
                expect(
                    vocabulary.hints(in: "Solo Leveling (Manhwa)").contains("manhwa"), "type hints")

                // where a query's time actually goes. isolated by picking seeds that
                // decline different blocks rather than by instrumenting the scorer:
                // a seed with no synopsis skips the embedding block, one with no year
                // skips era, so the differences are the block costs
                let scorer = try Scorer(bundle: bundle)
                let comics = Set(CatalogFormat.comics.map(\.rawValue))
                func time(_ row: Int) -> Double {
                    let started = Date()
                    _ = scorer.rank(row: row, ceiling: 1, types: comics, k: 20)
                    return Date().timeIntervalSince(started) * 1000
                }
                var withEmbedding = -1
                var withoutEmbedding = -1
                for row in 0..<n {
                    if withEmbedding < 0, hasEmbed[row] == 1,
                        year[row] != Int16(bundle.manifest.yearUnknown)
                    {
                        withEmbedding = row
                    }
                    if withoutEmbedding < 0, hasEmbed[row] == 0,
                        year[row] != Int16(bundle.manifest.yearUnknown)
                    {
                        withoutEmbedding = row
                    }
                    if withEmbedding >= 0 && withoutEmbedding >= 0 { break }
                }
                if withEmbedding >= 0 && withoutEmbedding >= 0 {
                    _ = time(withEmbedding)  // discard the first, it is still paging
                    let full = (0..<5).map { _ in time(withEmbedding) }.reduce(0, +) / 5
                    let noEmbed = (0..<5).map { _ in time(withoutEmbedding) }.reduce(0, +) / 5
                    log(
                        String(
                            format: "query cost - full %.0fms, without embedding block %.0fms, "
                                + "so embeddings are %.0fms (%.0f%%)",
                            full, noEmbed, full - noEmbed, 100 * (full - noEmbed) / full))
                }

                // step 5: the golden rankings. staged into the bundle only while this
                // is being verified - per D3 nothing ships, and ranking.json comes
                // back out once the scorer matches
                if let url = Foundation.Bundle.main.url(
                    forResource: "ranking", withExtension: "json")
                {
                    try bundle.rank(against: url, log: log)
                }

                if problems.isEmpty {
                    log("bundle self-check passed")
                } else {
                    AppLog.shared.log(
                        "bundle self-check FAILED - \(problems.joined(separator: ", "))",
                        level: .error, category: "recommender")
                }
            } catch let error as RecommenderError {
                // absence is the ordinary state on a machine that never had the files
                // copied in, so it is reported rather than raised. everything else is
                // a real fault in the bundle
                if case .unavailable = error {
                    log("no model in this build")
                } else {
                    AppLog.shared.log(
                        "model load FAILED - \(error.detail)",
                        level: .error, category: "recommender")
                }
            } catch {
                AppLog.shared.log(
                    "model load FAILED - \(error)",
                    level: .error, category: "recommender")
            }
        }
    }
#endif

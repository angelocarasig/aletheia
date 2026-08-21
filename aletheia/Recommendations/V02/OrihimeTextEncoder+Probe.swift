//
//  OrihimeTextEncoder+Probe.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

#if DEBUG
    import Foundation

    // fixtures/text-encoder.json's "input" already carries the "query: "
    // prefix baked in - stripped here since encode(_:) adds it itself, so
    // the two end up tokenizing the identical string
    extension OrihimeTextEncoder {
        static func probe(bundle: OrihimeBundle) async {
            let log = { (m: String) in AppLog.shared.log(m, category: "orihime") }
            do {
                struct Case: Decodable {
                    let input: String
                    let embedding: [Float]
                }
                let data = try bundle.blob("fixtures/text-encoder.json")
                let cases = try JSONDecoder().decode([Case].self, from: data)

                let encoder = OrihimeTextEncoder()
                try await encoder.prepare(bundle: bundle)

                var worst: Float = 1
                var checked = 0
                for testCase in cases.prefix(10) {
                    guard testCase.input.hasPrefix("query: ") else { continue }
                    let bareText = String(testCase.input.dropFirst("query: ".count))
                    let got = try await encoder.encode(bareText)
                    guard got.count == testCase.embedding.count else {
                        log(
                            "text encoder probe - dimension mismatch: got \(got.count), expected \(testCase.embedding.count)"
                        )
                        continue
                    }
                    let similarity = cosineSimilarity(got, testCase.embedding)
                    worst = min(worst, similarity)
                    checked += 1
                    if checked <= 3 {
                        log(
                            "text encoder probe - \"\(bareText.prefix(40))\" cosine \(String(format: "%.5f", similarity))"
                        )
                    }
                }
                log("text encoder probe - \(checked) cases, worst cosine \(String(format: "%.5f", worst))")
            } catch {
                AppLog.shared.log(
                    "text encoder probe FAILED - \(error)", level: .error, category: "orihime")
            }
        }

        private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
            var dot: Float = 0
            var magA: Float = 0
            var magB: Float = 0
            for i in 0..<a.count {
                dot += a[i] * b[i]
                magA += a[i] * a[i]
                magB += b[i] * b[i]
            }
            guard magA > 0, magB > 0 else { return 0 }
            return dot / (magA.squareRoot() * magB.squareRoot())
        }
    }
#endif

//
//  OrihimeCoverEncoder+Probe.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO

    // fixtures/cover-encoder/expected.json holds the projected 128-d vector,
    // not the raw 512-d encoder output - verifying against it exercises the
    // encoder and OrihimeCoverProjection together, the same pipeline a real
    // query runs
    extension OrihimeCoverEncoder {
        static func probe(bundle: OrihimeBundle) async {
            let log = { (m: String) in AppLog.shared.log(m, category: "orihime") }
            do {
                struct Case: Decodable {
                    let catalogId: Int
                    let image: String
                    let projected: [Float]
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let data = try bundle.blob("fixtures/cover-encoder/expected.json")
                let cases = try decoder.decode([Case].self, from: data)

                let encoder = OrihimeCoverEncoder()
                try await encoder.prepare(bundle: bundle)
                let projection = try OrihimeCoverProjection(bundle: bundle)

                var worst: Float = 1
                var checked = 0
                for testCase in cases.prefix(10) {
                    let imageData = try bundle.blob("fixtures/cover-encoder/\(testCase.image)")
                    guard
                        let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
                    else {
                        log("cover encoder probe - couldn't decode \(testCase.image)")
                        continue
                    }
                    let raw = try await encoder.encode(cgImage)
                    let got = try projection.project(raw)
                    guard got.count == testCase.projected.count else {
                        log(
                            "cover encoder probe - dimension mismatch: got \(got.count), expected \(testCase.projected.count)"
                        )
                        continue
                    }
                    let similarity = cosineSimilarity(got, testCase.projected)
                    worst = min(worst, similarity)
                    checked += 1
                    if checked <= 3 {
                        log(
                            "cover encoder probe - catalogId \(testCase.catalogId) cosine \(String(format: "%.5f", similarity))"
                        )
                    }
                }
                log("cover encoder probe - \(checked) cases, worst cosine \(String(format: "%.5f", worst))")
            } catch {
                AppLog.shared.log(
                    "cover encoder probe FAILED - \(error)", level: .error, category: "orihime")
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

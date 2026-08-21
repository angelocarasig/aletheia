//
//  OrihimeBundle+Probe.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

#if DEBUG
    import BackgroundAssets
    import Foundation

    // temporary - proves the loader end to end against the real downloaded pack before any
    // adapter or picker entry exists. delete once phase 2's OrihimeRecommender and its own
    // wiring through Compositor supersede this
    extension OrihimeBundle {
        static func probe() async {
            let log = { (m: String) in AppLog.shared.log(m, category: "orihime") }
            do {
                // assetPack(withID:) can answer from a manifest the device cached before
                // this pack existed on the server - forcing a refresh first is what
                // checkForUpdates exists for, per BAAssetPackManager's own header doc
                _ = try await AssetPackManager.shared.checkForUpdates()

                let pack = try await AssetPackManager.shared.assetPack(withID: "orihime-2-0-0")
                log("orihime probe - requesting orihime-2-0-0 (\(pack.downloadSize) bytes)")
                try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
                log("orihime probe - orihime-2-0-0 is now locally available")

                let bundle = try OrihimeBundle.load(
                    from: .assetPack(id: "orihime-2-0-0", root: "orihime-2-0-0-2026.08"))
                log("pack schema \(bundle.manifest.packSchema), built \(bundle.manifest.builtAt)")

                let seeds = bundle.manifest.counts.seeds
                let k = bundle.manifest.counts.k
                let titleCount = bundle.manifest.corpus.titles

                let rows = try bundle.array("rails/rows.npy", of: Int32.self)
                let scores = try bundle.array("rails/scores.npy", of: Float16.self)
                let seedRows = try bundle.array("rails/seed_rows.npy", of: Int32.self)
                let titles = try bundle.array("titles.npy", of: Int64.self)
                let excluded = try bundle.array("excluded.npy", of: UInt8.self)
                let flagWeights = try bundle.array(
                    "models/student/student-linear.npz/flag_weights.npy", of: Float.self)
                let thresholds = try bundle.array(
                    "models/student/student-linear.npz/thresholds.npy", of: Float.self)
                let coverMean = try bundle.array(
                    "params/cover-projection.npz/mean.npy", of: Float.self)
                let coverComponents = try bundle.array(
                    "params/cover-projection.npz/components.npy", of: Float.self)

                var problems: [String] = []
                func expect(_ ok: Bool, _ what: String) {
                    if !ok { problems.append(what) }
                }
                expect(rows.count == seeds * k, "rails/rows.npy \(rows.count) != seeds*k")
                expect(scores.count == seeds * k, "rails/scores.npy \(scores.count) != seeds*k")
                expect(seedRows.count == seeds, "rails/seed_rows.npy \(seedRows.count) != seeds")
                expect(titles.count == titleCount, "titles.npy \(titles.count) != titleCount")
                expect(excluded.count == titleCount, "excluded.npy \(excluded.count) != titleCount")
                expect(flagWeights.count == 56 * 3496, "flag_weights \(flagWeights.count)")
                expect(thresholds.count == 56, "thresholds \(thresholds.count)")
                expect(coverMean.count == 512, "cover-projection mean \(coverMean.count)")
                expect(
                    coverComponents.count == 128 * 512,
                    "cover-projection components \(coverComponents.count)")

                if problems.isEmpty {
                    log("orihime bundle self-check passed")
                } else {
                    AppLog.shared.log(
                        "orihime bundle self-check FAILED - \(problems.joined(separator: ", "))",
                        level: .error, category: "orihime")
                }
            } catch {
                AppLog.shared.log(
                    "orihime probe FAILED - \(error)", level: .error, category: "orihime")
            }
        }
    }
#endif

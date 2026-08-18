//
//  Compositor+Registry.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import GRDB

extension Compositor {
    struct Registry: Sendable {
        let sources: [Source]

        private let database: DatabaseClient
        private let sourcesBySlug: [String: Source]

        // sorted once here rather than at each call site: declaration order in
        // Compositor is an implementation detail, and every screen that lists
        // sources wants the same answer - everything else alphabetically, adult
        // sources alphabetically after them
        init(sources: [Source], database: DatabaseClient) {
            self.sources = sources.sorted { lhs, rhs in
                let left = lhs.descriptor.adultOnly
                let right = rhs.descriptor.adultOnly

                guard left == right else { return !left }
                return lhs.descriptor.name.localizedStandardCompare(rhs.descriptor.name)
                    == .orderedAscending
            }
            self.database = database
            self.sourcesBySlug = Dictionary(
                uniqueKeysWithValues: sources.map { ($0.descriptor.slug, $0) })
        }

        func source(slug: String) -> Source? {
            sourcesBySlug[slug]
        }

        func seed() async {
            let records = sources.map { SourceRecord(descriptor: $0.descriptor) }
            do {
                try await database.writer.write { db in
                    try SourceRecord.reconcile(with: records, in: db)
                }
                AppLog.shared.log("seeded \(records.count) source(s) into DB", category: "seed")
            } catch {
                AppLog.shared.log("seed FAILED - \(error)", level: .error, category: "seed")
            }
        }
    }
}

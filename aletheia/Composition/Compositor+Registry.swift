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
        
        init(sources: [Source], database: DatabaseClient) {
            self.sources = sources
            self.database = database
            self.sourcesBySlug = Dictionary(uniqueKeysWithValues: sources.map { ($0.descriptor.slug, $0) })
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
                AppLog.shared.log("seed FAILED — \(error)", category: "seed")
            }
        }
    }
}

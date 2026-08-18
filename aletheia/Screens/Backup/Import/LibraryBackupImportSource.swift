//
//  LibraryBackupImportSource.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import Foundation

// turns an already-decoded backup into rows, resolving each entry's
// exact-match fast path up front: if the backed-up primary origin's source
// is still installed, the candidate is already known and no live search is
// needed. decoding itself happens before this is ever constructed
// (AletheiaBackupImportScreen) - MigrationComposer.start() swallows a
// throw from fetch() into a generic string, which is the wrong place to
// lose a typed LibraryBackupEnvelope.EnvelopeError the screen wants to
// show a specific message for (docs/features/library-backup.md §2's
// "newer version" case included)
struct LibraryBackupImportSource: MigrationSource {
    let backup: LibraryBackup
    let registry: Compositor.Registry

    func fetch() async throws -> [LibraryBackupEntry] {
        backup.series.enumerated().map { index, entry in
            let primary = entry.origins.min { $0.priority < $1.priority }

            var resolvedCandidate: MigrationCandidate?
            if let primary, registry.source(slug: primary.sourceSlug) != nil {
                resolvedCandidate = MigrationCandidate(
                    sourceSlug: primary.sourceSlug,
                    stub: SeriesStub(slug: primary.seriesSlug, title: entry.preferredTitle, cover: nil)
                )
            }

            return LibraryBackupEntry(
                id: index,
                title: entry.preferredTitle,
                seriesEntry: entry,
                primaryOrigin: primary,
                resolvedCandidate: resolvedCandidate
            )
        }
    }
}

//
//  AletheiaBackupImportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

// pick a file, then the queue - no "which sources to search" step first,
// unlike source/disconnected migration. those flows narrow a deliberate
// move; restore's whole point is bringing everything back, so every
// installed source is searched by default for whatever entry's own source
// is gone. nothing here writes to the database - every write happens
// inside LibraryBackupCommitter.commit
struct AletheiaBackupImportScreen: View {
    var onFinish: () -> Void

    @State private var showingPicker = true
    @State private var composer: MigrationComposer<LibraryBackupEntry>?
    @State private var loading = false
    @State private var loadFailure: String?
    @State private var showingQueue = false

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadFailure {
                ContentUnavailableView {
                    Label("Couldn't Read Backup", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadFailure)
                } actions: {
                    Button("Choose a Different File") { showingPicker = true }
                }
            } else {
                ContentUnavailableView {
                    Label("From an Aletheia Backup", systemImage: "shippingbox")
                } description: {
                    Text("Choose a backup file to restore your library from.")
                } actions: {
                    Button("Choose File") { showingPicker = true }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Restore Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark", action: onFinish)
                    .labelStyle(.iconOnly)
            }
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.aletheiaBackup, .data]) { result in
            switch result {
            case let .success(url):
                Task { await load(from: url) }
            case .failure:
                break
            }
        }
        .navigationDestination(isPresented: $showingQueue) {
            if let composer {
                OriginMigrationScreen(composer: composer, savedLabel: "Restored", onFinish: onFinish)
            }
        }
    }

    private func load(from url: URL) async {
        loading = true
        loadFailure = nil
        defer { loading = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let backup = try LibraryBackupCodec.decode(data)
            let newComposer = MigrationComposer(
                source: LibraryBackupImportSource(backup: backup, registry: compositor.registry),
                searching: LiveMigrationSearcher(),
                committing: LibraryBackupCommitter(
                    database: compositor.database,
                    registry: compositor.registry,
                    refresher: compositor.refresh
                ),
                registry: compositor.registry,
                precheckLabel: "Already Restored",
                initialMatch: { entry in
                    entry.resolvedCandidate.map { .found([$0], selected: $0) } ?? .idle
                }
            )
            // every installed source, not a picked subset - restore's own
            // job is finding everything again, not narrowing where from
            newComposer.selectedSourceSlugs = Set(newComposer.availableSources.map(\.descriptor.slug))

            await newComposer.start()

            guard newComposer.loadFailure == nil else {
                loadFailure = newComposer.loadFailure
                return
            }
            guard !newComposer.rows.isEmpty else {
                loadFailure = "This backup doesn't have any series in it."
                return
            }

            composer = newComposer
            showingQueue = true
        } catch let error as LibraryBackupEnvelope.EnvelopeError {
            loadFailure = envelopeMessage(error)
        } catch {
            loadFailure = Failure(error, fallback: "Couldn't read that file").sentence
        }
    }

    private func envelopeMessage(_ error: LibraryBackupEnvelope.EnvelopeError) -> String {
        switch error {
        case .badMagic:
            "That doesn't look like an aletheia backup file."
        case .truncated, .compressionFailed:
            "That backup file is damaged."
        case let .newerVersion(version):
            "This backup was made with a newer version of the app (format v\(version)). Update to restore it."
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AletheiaBackupImportScreen(onFinish: {})
    }
}

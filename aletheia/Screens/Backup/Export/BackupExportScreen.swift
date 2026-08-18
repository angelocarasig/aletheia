//
//  BackupExportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

// one action, one screen: build the whole library into a LibraryBackup
// message (LibraryBackupBuilder), encode it (LibraryBackupCodec), hand the
// file to the system's own document-export picker. nothing here writes to
// the database - export is read-only by nature
//
// .fileExporter rather than ShareLink: ShareLink's own "Save to Files" is a
// known, widely-reported platform bug with Transferable items (both
// DataRepresentation and FileRepresentation - filed against multiple iOS
// versions on Apple's developer forums), not something fixable from this
// side. .fileExporter is Apple's own API for "save this to a location I
// pick" and does not go through that path at all
struct BackupExportScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var phase: Phase = .idle
    @State private var showingExporter = false

    private enum Phase: Equatable {
        case idle
        case exporting
        case ready(LibraryBackupDocument, filename: String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: dimensions.spacing.space24) {
            Spacer()

            VStack(spacing: dimensions.spacing.space12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.brand)
                    .symbolEffect(.bounce, value: phase == .exporting)

                Text("Every series, its progress, and its tracker links go into one file you can restore from later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, dimensions.screenMargin)
            }

            if case let .failed(reason) = phase {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.dangerText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, dimensions.screenMargin)
            }

            Spacer()

            Action
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space24)
        }
        .navigationTitle("Backup Your Library")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.settle, value: phase)
        .fileExporter(
            isPresented: $showingExporter,
            document: exportedDocument,
            contentType: .aletheiaBackup,
            defaultFilename: exportedFilename
        ) { result in
            if case let .failure(error) = result {
                phase = .failed(Failure(error, fallback: "Couldn't save the backup").sentence)
            }
        }
    }

    private var exportedDocument: LibraryBackupDocument? {
        if case let .ready(document, _) = phase { document } else { nil }
    }

    private var exportedFilename: String? {
        if case let .ready(_, filename) = phase { filename } else { nil }
    }

    @ViewBuilder
    private var Action: some View {
        switch phase {
        case .idle, .failed:
            Button("Export Library") { Task { await export() } }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: dimensions.touchTarget)

        case .exporting:
            HStack(spacing: dimensions.spacing.space8) {
                ProgressView()
                Text("Exporting")
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: dimensions.touchTarget)

        case .ready:
            Button { showingExporter = true } label: {
                HStack(spacing: dimensions.spacing.space8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save Backup")
                }
            }
            .buttonStyle(.glassProminent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: dimensions.touchTarget)
        }
    }

    private func export() async {
        phase = .exporting

        do {
            let backup = try await LibraryBackupBuilder.build(database: compositor.database)
            let data = try LibraryBackupCodec.encode(backup)
            let stamp = Date.now.formatted(.iso8601.year().month().day())
            phase = .ready(LibraryBackupDocument(data: data), filename: "aletheia-backup-\(stamp)")
            showingExporter = true
        } catch {
            phase = .failed(Failure(error, fallback: "Couldn't build the backup").sentence)
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        BackupExportScreen()
    }
}

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
// file to the share sheet. nothing here writes to the database - export is
// read-only by nature
struct BackupExportScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var phase: Phase = .idle

    private enum Phase: Equatable {
        case idle
        case exporting
        case ready(LibraryBackupFile)
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

        case let .ready(file):
            ShareLink(item: file, preview: SharePreview(file.filename)) {
                HStack(spacing: dimensions.spacing.space8) {
                    Image(systemName: "square.and.arrow.up")
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
            phase = .ready(LibraryBackupFile(data: data))
        } catch {
            phase = .failed(Failure(error, fallback: "Couldn't build the backup").sentence)
        }
    }
}

// a plain Data value has no filename or content type of its own - this is
// what gives the share sheet both, so it offers "Save to Files" with a real
// .althbackup extension rather than a generic "data" attachment
private struct LibraryBackupFile: Transferable, Equatable {
    let data: Data
    let filename: String

    init(data: Data) {
        self.data = data
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        self.filename = "aletheia-backup-\(stamp).althbackup"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .altheliaBackup) { file in
            file.data
        }
        .suggestedFileName { $0.filename }
    }
}

private extension UTType {
    static let altheliaBackup = UTType(exportedAs: "moe.aletheia.backup", conformingTo: .data)
}

// MARK: - Previews

#Preview {
    NavigationStack {
        BackupExportScreen()
    }
}

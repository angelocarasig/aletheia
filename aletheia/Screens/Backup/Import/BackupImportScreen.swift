//
//  BackupImportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct BackupImportScreen: View {
    var onFinish: () -> Void

    @State private var phase: Phase
    @State private var showingPicker: Bool
    @State private var confirmingWipe: LibraryBackup?
    @Namespace private var glass

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    enum Phase: Equatable {
        case idle
        case reading
        case ready(LibraryBackup, summary: LibraryBackupSummary)
        case restoring
        case restored(LibraryBackupRestorer.Summary)
        case failed(String)
    }

    init(onFinish: @escaping () -> Void, phase: Phase = .idle) {
        self.onFinish = onFinish
        _phase = State(initialValue: phase)
        _showingPicker = State(initialValue: phase == .idle)
    }

    private var isReady: Bool {
        if case .ready = phase { true } else { false }
    }

    var body: some View {
        ZStack {
            if case let .failed(reason) = phase {
                Failed(reason)
                    .transition(.opacity)
            } else {
                Content
                    .transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationTitle("Restore Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark", action: onFinish)
                    .labelStyle(.iconOnly)
                    .disabled(phase == .restoring)
            }
        }
        .interactiveDismissDisabled(phase == .restoring)
        .sensoryFeedback(.success, trigger: isReady) { _, ready in ready }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.aletheiaBackup, .data]) { result in
            switch result {
            case let .success(url): Task { await load(from: url) }
            case .failure: break
            }
        }
        .alert(
            "Wipe and Restore Library?",
            isPresented: Binding(
                get: { confirmingWipe != nil },
                set: { if !$0 { confirmingWipe = nil } }
            ),
            presenting: confirmingWipe
        ) { backup in
            Button("Cancel", role: .cancel) {}
            Button("Wipe and Restore", role: .destructive) {
                Task { await restore(backup) }
            }
        } message: { _ in
            Text("This replaces your entire library with what's in this backup. Series and chapters not in the backup will be removed. This can't be undone.")
        }
    }

    private var Content: some View {
        ScrollView {
            VStack(spacing: dimensions.spacing.space24) {
                GlassEffectContainer(spacing: dimensions.spacing.space16) {
                    HStack(spacing: dimensions.spacing.space16) {
                        BackupPhaseIcon(
                            systemImage: iconName,
                            tint: iconTint,
                            tintOpacity: isReady ? 0.18 : 0.15,
                            isSpinning: phase == .reading,
                            bounceTrigger: isReady,
                            namespace: glass
                        )

                        VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                            Text(title)
                                .font(.headline)
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(dimensions.spacing.space16)
                    .glassEffect(.regular, in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
                }

                if case let .ready(backup, summary) = phase {
                    ExportedRow(backup)

                    LibraryBackupManifestGroup(
                        title: "Library",
                        rows: [
                            ("book.closed", "Series", summary.seriesCount),
                            ("square.stack", "Chapters", summary.chapterCount)
                        ]
                    )

                    LibraryBackupManifestGroup(
                        title: "Vocabulary",
                        rows: [
                            ("tag", "Tags", summary.tagCount),
                            ("person", "Authors", summary.authorCount),
                            ("folder", "Collections", summary.collectionCount),
                            ("link", "Tracker Links", summary.trackerLinkCount)
                        ]
                    )

                    Text("Your library will be replaced to match this backup exactly. Series still on an installed source attach automatically; others are added as disconnected and can be relinked later.")
                        .font(.caption)
                        .foregroundStyle(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, dimensions.spacing.space8)
                }

                if case let .restored(summary) = phase {
                    LibraryBackupManifestGroup(
                        title: "Restored",
                        rows: [
                            ("checkmark.circle", "Restored", summary.restoredCount),
                            ("bolt.slash", "Disconnected", summary.disconnectedCount),
                            ("trash", "Removed", summary.removedCount)
                        ]
                    )

                    if !summary.failures.isEmpty {
                        FailuresList(summary.failures)
                    }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space16)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaInset(edge: .bottom) {
            Action
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space8)
        }
    }

    private var iconName: String? {
        switch phase {
        case .idle: "tray.and.arrow.down"
        case .reading, .restoring: "progress.indicator"
        case .ready: "checkmark.circle.fill"
        case .restored: "checkmark.seal.fill"
        case .failed: nil
        }
    }

    private var iconTint: Color {
        switch phase {
        case .idle, .reading, .restoring: .brand
        case .ready, .restored: .success
        case .failed: .secondary
        }
    }

    private var title: String {
        switch phase {
        case .idle: "Restore from a Backup"
        case .reading: "Reading Backup"
        case .ready: "Backup Found"
        case .restoring: "Restoring Library"
        case .restored: "Library Restored"
        case .failed: ""
        }
    }

    private var description: String {
        switch phase {
        case .idle:
            "Choose a backup file to see what's inside before restoring anything."
        case .reading:
            "Opening the file."
        case .ready:
            "Review what's inside, then restore it into your library."
        case .restoring:
            "Writing series, chapters, and links back into your library."
        case .restored:
            "Your library now matches this backup."
        case .failed:
            ""
        }
    }

    private func ExportedRow(_ backup: LibraryBackup) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: dimensions.spacing.space4) {
                Text("Exported")
                LiveRelativeText(date: Date(timeIntervalSince1970: TimeInterval(backup.exportedDate)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var Action: some View {
        switch phase {
        case .idle:
            BackupActionSlab(icon: "doc.badge.plus", label: "Choose File") {
                showingPicker = true
            }
            .transition(.opacity)

        case .reading:
            BackupActionSlab(icon: nil, label: "Reading", tinted: false, isLoading: true) {}
                .transition(.opacity)

        case let .ready(backup, _):
            BackupActionSlab(icon: "arrow.triangle.2.circlepath", label: "Restore Library") {
                confirmingWipe = backup
            }
            .transition(.opacity)

        case .restoring:
            BackupActionSlab(icon: nil, label: "Restoring", tinted: false, isLoading: true) {}
                .transition(.opacity)

        case .restored:
            BackupActionSlab(icon: "checkmark", label: "Done", action: onFinish)
                .transition(.opacity)

        case .failed:
            EmptyView()
        }
    }

    private func FailuresList(_ failures: [LibraryBackupRestorer.Summary.Failure]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Text("Couldn't Restore")
                .font(.subheadline.weight(.semibold))

            ForEach(failures, id: \.title) { failure in
                VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                    Text(failure.title)
                        .font(.callout)
                    Text(failure.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(dimensions.spacing.space16)
        .background(.thinMaterial, in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
    }

    private func Failed(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Read Backup", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            Button("Choose a Different File") { showingPicker = true }
                .buttonStyle(.glassProminent)
                .tint(.brand)
        }
    }

    private func load(from url: URL) async {
        phase = .reading

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let backup = try LibraryBackupCodec.decode(data)
            phase = .ready(backup, summary: LibraryBackupSummary(decoding: backup))
        } catch let error as LibraryBackupEnvelope.EnvelopeError {
            phase = .failed(envelopeMessage(error))
        } catch {
            phase = .failed(Failure(error, fallback: "Couldn't read that file").sentence)
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

    private func restore(_ backup: LibraryBackup) async {
        phase = .restoring
        let summary = await LibraryBackupRestorer.restore(
            backup,
            database: compositor.database,
            registry: compositor.registry
        )
        phase = .restored(summary)
    }
}

// MARK: - Previews

#if DEBUG
private struct ImportPreview: View {
    @State private var index = 0

    private static let backup: LibraryBackup = {
        var backup = LibraryBackup()
        backup.exportedByAppVersion = "1.0"
        backup.exportedDate = Int64(Date.now.addingTimeInterval(-3 * 24 * 60 * 60).timeIntervalSince1970)
        backup.series = (0..<142).map { _ in LibraryBackup.SeriesEntry() }
        return backup
    }()

    private static let summary = LibraryBackupSummary(
        seriesCount: 142,
        chapterCount: 12480,
        tagCount: 58,
        authorCount: 96,
        collectionCount: 6,
        trackerLinkCount: 37
    )

    private static let restoredSummary = LibraryBackupRestorer.Summary(
        restoredCount: 138,
        disconnectedCount: 3,
        removedCount: 5,
        failures: [.init(title: "Some Series", reason: "Couldn't restore this series")]
    )

    private static let states: [(name: String, phase: BackupImportScreen.Phase)] = [
        ("Idle", .idle),
        ("Reading", .reading),
        ("Ready", .ready(backup, summary: summary)),
        ("Restoring", .restoring),
        ("Restored", .restored(restoredSummary)),
        ("Failed", .failed("That doesn't look like an aletheia backup file."))
    ]

    var body: some View {
        NavigationStack {
            BackupImportScreen(onFinish: {}, phase: Self.states[index].phase)
                // @State only reads init's value once, so a fresh .id per
                // tap is what makes cycling the index actually redraw
                .id(index)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Self.states[index].name) {
                            index = (index + 1) % Self.states.count
                        }
                    }
                }
        }
    }
}

#Preview("Import phases") {
    ImportPreview()
}
#endif

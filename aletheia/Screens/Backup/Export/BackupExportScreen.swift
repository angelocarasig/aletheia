//
//  BackupExportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// .fileExporter rather than ShareLink - ShareLink's own "Save to Files" is
// a widely-reported platform bug with Transferable items, not fixable here
struct BackupExportScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var phase: Phase
    @State private var summary: LibraryBackupSummary?
    @State private var lastBackupDate: Date?
    @State private var showingExporter = false
    @Namespace private var glass

    enum Phase: Equatable {
        case idle
        case exporting
        case ready(LibraryBackupDocument, filename: String)
        case failed(String)
    }

    init(phase: Phase = .idle, summary: LibraryBackupSummary? = nil, lastBackupDate: Date? = nil) {
        _phase = State(initialValue: phase)
        _summary = State(initialValue: summary)
        _lastBackupDate = State(initialValue: lastBackupDate)
    }

    private var isReady: Bool {
        if case .ready = phase { true } else { false }
    }

    var body: some View {
        ZStack {
            if case .failed(let reason) = phase {
                Failed(reason)
                    .transition(.opacity)
            } else {
                Content
                    .transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationTitle("Backup Your Library")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: isReady) { _, ready in ready }
        .task {
            guard summary == nil else { return }
            summary = try? await LibraryBackupBuilder.summary(database: compositor.database)
        }
        .task {
            lastBackupDate =
                UserDefaults.standard.object(
                    forKey: Preferences.Key.libraryBackupExportedDate
                ) as? Date
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportedDocument,
            contentType: .aletheiaBackup,
            defaultFilename: exportedFilename
        ) { result in
            switch result {
            case .success:
                let now = Date.now
                UserDefaults.standard.set(now, forKey: Preferences.Key.libraryBackupExportedDate)
                lastBackupDate = now
            case .failure(let error):
                phase = .failed(Failure(error, fallback: "Couldn't save the backup").sentence)
            }
        }
    }

    private var exportedDocument: LibraryBackupDocument? {
        if case .ready(let document, _) = phase { document } else { nil }
    }

    private var exportedFilename: String? {
        if case .ready(_, let filename) = phase { filename } else { nil }
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
                            isSpinning: phase == .exporting,
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
                    .glassEffect(
                        .regular,
                        in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
                }

                LastBackupRow

                LibraryBackupManifestGroup(
                    title: "Library",
                    rows: [
                        ("book.closed", "Series", summary?.seriesCount),
                        ("square.stack", "Chapters", summary?.chapterCount),
                    ]
                )

                LibraryBackupManifestGroup(
                    title: "Vocabulary",
                    rows: [
                        ("tag", "Tags", summary?.tagCount),
                        ("person", "Authors", summary?.authorCount),
                        ("folder", "Collections", summary?.collectionCount),
                        ("link", "Tracker Links", summary?.trackerLinkCount),
                    ]
                )

                Text(
                    "Cover images and downloaded chapters stay on this device - a restore rebuilds them from your sources."
                )
                .font(.caption)
                .foregroundStyle(.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, dimensions.spacing.space8)
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
        case .idle: "shippingbox"
        case .exporting: "progress.indicator"
        case .ready: "checkmark.circle.fill"
        case .failed: nil
        }
    }

    private var iconTint: Color {
        switch phase {
        case .idle, .exporting: .brand
        case .ready: .success
        case .failed: .secondary
        }
    }

    private var title: String {
        switch phase {
        case .idle: "Backup Your Library"
        case .exporting: "Exporting"
        case .ready: "Backup Ready"
        case .failed: ""
        }
    }

    private var description: String {
        switch phase {
        case .idle:
            "Everything below goes into one file you can restore from later."
        case .exporting:
            "Reading your library."
        case .ready(let document, _):
            "\(byteCount(document.data.count)) - save it somewhere safe, like iCloud Drive or Files."
        case .failed:
            ""
        }
    }

    private func byteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private var LastBackupRow: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if let lastBackupDate {
                    HStack(spacing: dimensions.spacing.space4) {
                        Text("Last backed up")
                        LiveRelativeText(date: lastBackupDate)
                    }
                } else {
                    Text("You haven't backed up before")
                }
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
            BackupActionSlab(icon: "square.and.arrow.up.on.square", label: "Export Library") {
                Task { await export() }
            }
            .transition(.opacity)

        case .exporting:
            BackupActionSlab(icon: nil, label: "Exporting", tinted: false, isLoading: true) {}
                .transition(.opacity)

        case .ready:
            BackupActionSlab(icon: "square.and.arrow.down", label: "Save Backup") {
                showingExporter = true
            }
            .transition(.opacity)

        case .failed:
            EmptyView()
        }
    }

    private func Failed(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Export", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            Button("Try Again") { Task { await export() } }
                .buttonStyle(.glassProminent)
                .tint(.brand)
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

#if DEBUG
    private struct ExportPreview: View {
        @State private var index = 0

        private static let summary = LibraryBackupSummary(
            seriesCount: 142,
            chapterCount: 12480,
            tagCount: 58,
            authorCount: 96,
            collectionCount: 6,
            trackerLinkCount: 37
        )

        private static let states: [(name: String, phase: BackupExportScreen.Phase)] = [
            ("Idle", .idle),
            ("Exporting", .exporting),
            (
                "Ready",
                .ready(
                    LibraryBackupDocument(data: Data("preview".utf8)),
                    filename: "aletheia-backup-2026-08-18")
            ),
            ("Failed", .failed("The database could not be read.")),
        ]

        var body: some View {
            NavigationStack {
                BackupExportScreen(
                    phase: Self.states[index].phase,
                    summary: Self.summary,
                    lastBackupDate: .now.addingTimeInterval(-2 * 24 * 60 * 60)
                )
                // @State only reads init's value once, so a fresh .id per
                // tap is what makes cycling the index actually redraw
                .id(index)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(Self.states[index].name) {
                            index = (index + 1) % Self.states.count
                        }
                    }
                }
            }
        }
    }

    #Preview("Export phases") {
        ExportPreview()
    }
#endif

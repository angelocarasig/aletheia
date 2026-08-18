//
//  MigrationsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// one settings destination for moving a library around - between sources,
// in from a tracker, or out to a file - rather than a single
// "Restore from Tracker" card sitting in Reading with nothing to group it
// under. Import has the one real flow; Export has the one real flow
// (backup) plus two scaffolded entries (Recent Backups, Auto Backup)
struct MigrationsScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var showingTrackerRestore = false
    @State private var showingSourceMigration = false
    @State private var showingDisconnectedMigration = false
    @State private var showingOtherReaderImport = false
    @State private var showingBackupImport = false
    @State private var showingBackupExport = false
    @State private var showingRecentBackups = false
    @State private var showingAutoBackup = false

    @State private var hasDisconnectedSources = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Migrate")

                    Card(
                        "Move Between Sources",
                        systemImage: "arrow.left.arrow.right",
                        detail: "Move a series from one installed source to another"
                    ) { showingSourceMigration = true }

                    // "disconnected" here is DetailsSources' DISCONNECTED badge state
                    // (origin.sourceId no longer resolves to an installed source) -
                    // not "detached" (MetadataRecord's no-tracker-link state)
                    Card(
                        "Manage Disconnected Sources",
                        systemImage: "cable.connector.slash",
                        detail: hasDisconnectedSources
                            ? "Move a series off a source that's no longer installed"
                            : "No disconnected sources right now",
                        enabled: hasDisconnectedSources
                    ) { showingDisconnectedMigration = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Import")

                    Card(
                        "From a Tracker",
                        systemImage: "tray.and.arrow.down",
                        detail: "Rebuild your library from a tracker's list"
                    ) { showingTrackerRestore = true }

                    Card(
                        "From Another Reader",
                        systemImage: "square.and.arrow.down",
                        detail: "Bring your library over from Tachiyomi, Mihon, or another reader"
                    ) { showingOtherReaderImport = true }

                    Card(
                        "From Backup",
                        systemImage: "shippingbox",
                        detail: "Restore your library from your own exported backup"
                    ) { showingBackupImport = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Export")

                    Card(
                        "Create Backup",
                        systemImage: "square.and.arrow.up",
                        detail: "Save your library to a file you can restore later"
                    ) { showingBackupExport = true }

                    Card(
                        "Recent Backups",
                        systemImage: "clock.arrow.circlepath",
                        detail: "Download a backup you made before"
                    ) { showingRecentBackups = true }

                    Card(
                        "Auto Backup",
                        systemImage: "arrow.triangle.2.circlepath",
                        detail: "Back up your library on a schedule"
                    ) { showingAutoBackup = true }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Migrations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshDisconnectedCheck() }
        .onChange(of: showingDisconnectedMigration) { _, showing in
            guard !showing else { return }
            Task { await refreshDisconnectedCheck() }
        }
        .navigationDestination(isPresented: $showingOtherReaderImport) {
            OtherReaderImportScreen()
        }
        .navigationDestination(isPresented: $showingBackupExport) {
            BackupExportScreen()
        }
        .navigationDestination(isPresented: $showingRecentBackups) {
            RecentBackupsScreen()
        }
        .navigationDestination(isPresented: $showingAutoBackup) {
            AutoBackupScreen()
        }
        .sheet(isPresented: $showingBackupImport) {
            NavigationStack {
                BackupImportScreen(onFinish: { showingBackupImport = false })
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingSourceMigration) {
            NavigationStack {
                SourceMigrationScreen(onFinish: { showingSourceMigration = false })
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingDisconnectedMigration) {
            NavigationStack {
                DisconnectedSourceMigrationScreen(onFinish: { showingDisconnectedMigration = false }
                )
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingTrackerRestore) {
            NavigationStack {
                TrackerRestoreSetupScreen(onFinish: { showingTrackerRestore = false })
            }
            // must stay disabled - a swipe dismiss would skip onFinish and bypass the
            // queue screen's own unsaved-changes warning on Close
            .interactiveDismissDisabled(true)
        }
    }

    private func refreshDisconnectedCheck() async {
        let entries = try? await DisconnectedOriginMigrationSource(database: compositor.database)
            .fetch()
        hasDisconnectedSources = !(entries?.isEmpty ?? true)
    }

    private func Card(
        _ title: String,
        systemImage: String,
        detail: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: Layout.glyphWidth)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
        .opacity(enabled ? 1 : 0.5)
        .tappable(action: action)
        .disabled(!enabled)
        .animation(.settle, value: enabled)
    }

    private enum Layout {
        static let glyphWidth: CGFloat = 28
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        MigrationsScreen()
    }
}

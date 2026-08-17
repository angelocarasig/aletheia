//
//  SettingsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// the app's first settings destination. it exists because tracker sign-in was
// the third settings-shaped thing to need a home after refresh cadence and the
// reader's own panel, and each had been bolted onto a different tab's chrome
struct SettingsScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var showingTracking = false
    @State private var showingRefresh = false
    @State private var showingMetadataRefresh = false
    @State private var showingBackupRestore = false
    @State private var showingLogs = false
    @State private var showingImpressions = false

    private enum Layout {
        static let glyphWidth: CGFloat = 28
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Reading")

                    Card(
                        "Tracking",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        // what is connected, answered before the destination is
                        // opened rather than inside it
                        detail: connected ?? "Not connected"
                    ) { showingTracking = true }

                    Card(
                        "Library Updates",
                        systemImage: "arrow.clockwise",
                        detail: "When new chapters are checked for"
                    ) { showingRefresh = true }

                    Card(
                        "Metadata Updates",
                        systemImage: "text.append",
                        detail: "How often series details are refreshed"
                    ) { showingMetadataRefresh = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Data & Storage")

                    Card(
                        "Recommendations",
                        systemImage: "sparkle.magnifyingglass",
                        detail: "What the model showed, and what came of it"
                    ) { showingImpressions = true }

                    Card(
                        "Backup & Restore",
                        systemImage: "externaldrive.badge.timemachine",
                        detail: "Move your library in or out"
                    ) { showingBackupRestore = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Diagnostics")

                    // shipped rather than DEBUG-gated: the run worth reading is
                    // the one that already crashed, on a device with no Xcode
                    // attached, which is exactly the build a condition would
                    // have excluded
                    Card(
                        "Logs",
                        systemImage: "text.alignleft",
                        detail: "What the app recorded, including last launch"
                    ) { showingLogs = true }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingTracking) { TrackingScreen() }
        .navigationDestination(isPresented: $showingRefresh) { RefreshSettingsScreen() }
        .navigationDestination(isPresented: $showingMetadataRefresh) { MetadataRefreshSettingsScreen() }
        .navigationDestination(isPresented: $showingBackupRestore) { BackupRestoreScreen() }
        .navigationDestination(isPresented: $showingLogs) { LogScreen() }
        .navigationDestination(isPresented: $showingImpressions) { ImpressionsScreen() }
        .task { compositor.trackers.hydrate() }
    }

    private func Card(
        _ title: String,
        systemImage: String,
        detail: String,
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

                // the string changes in place rather than the view being
                // replaced, so this is a content transition - a .transition
                // would never fire, because no branch is inserted or removed
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.settle, value: detail)
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
        .tappable(action: action)
    }

    private var connected: String? {
        let accounts = compositor.trackers.accounts.keys
        guard !accounts.isEmpty else { return nil }
        return Tracker.allCases
            .filter { accounts.contains($0) }
            .map(\.name)
            .joined(separator: " · ")
    }
}

// MARK: - Previews

// reads the real keychain for its one variable line, so this is a layout check
// rather than a state check - the subtitle says whatever this device is signed
// into, and "Not connected" only appears when it genuinely is not
#Preview {
    NavigationStack {
        SettingsScreen()
    }
}

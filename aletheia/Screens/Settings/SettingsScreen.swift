//
//  SettingsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

struct SettingsScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var showingTracking = false
    @State private var showingRefresh = false
    @State private var showingMetadataRefresh = false
    @State private var showingMigrations = false
    @State private var showingLogs = false
    @State private var showingRecommendations = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Reading")

                    SettingsCard(
                        title: "Tracking",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        detail: connected ?? "Not connected"
                    ) { showingTracking = true }

                    SettingsCard(
                        title: "Library Updates",
                        systemImage: "arrow.clockwise",
                        detail: "When new chapters are checked for"
                    ) { showingRefresh = true }

                    SettingsCard(
                        title: "Metadata Updates",
                        systemImage: "text.append",
                        detail: "How often series details are refreshed"
                    ) { showingMetadataRefresh = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Data & Storage")

                    SettingsCard(
                        title: "Recommendations",
                        systemImage: "sparkle.magnifyingglass",
                        detail: "Which model to use, and what came of it"
                    ) { showingRecommendations = true }

                    SettingsCard(
                        title: "Migrations",
                        systemImage: "externaldrive.badge.timemachine",
                        detail: "Move series in, out, or between sources"
                    ) { showingMigrations = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Diagnostics")

                    // shipped rather than DEBUG-gated - the crash worth reading has no Xcode attached
                    SettingsCard(
                        title: "Logs",
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
        .navigationDestination(isPresented: $showingMetadataRefresh) {
            MetadataRefreshSettingsScreen()
        }
        .navigationDestination(isPresented: $showingMigrations) { MigrationsScreen() }
        .navigationDestination(isPresented: $showingLogs) { LogScreen() }
        .navigationDestination(isPresented: $showingRecommendations) { RecommendationsScreen() }
        .task { compositor.trackers.hydrate() }
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

// reads the real keychain, so the "Tracking" detail reflects this device's actual
// signed-in state rather than mock data - not deterministic across devices
#Preview {
    NavigationStack {
        SettingsScreen()
    }
}

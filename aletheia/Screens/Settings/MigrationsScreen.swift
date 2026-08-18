//
//  MigrationsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// one settings destination for moving a library around - between sources,
// in from a tracker, or (eventually) out to a file - rather than a single
// "Restore from Tracker" card sitting in Reading with nothing to group it
// under. Migrate has its two scaffolded entries today and no logic behind
// either; Import has the one real flow; Export is where a future CBZ/backup-
// file export would land - see aletheia/CLAUDE.md's zlib note
struct MigrationsScreen: View {
    @Environment(\.dimensions) private var dimensions

    @State private var showingTrackerRestore = false
    @State private var showingSourceMigration = false
    @State private var showingDisconnectedMigration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Migrate")

                    Card(
                        "Between Sources",
                        systemImage: "arrow.left.arrow.right",
                        detail: "Move a series from one installed source to another"
                    ) { showingSourceMigration = true }

                    // "detached" already means something else in this codebase
                    // (a metadata row with no tracker link) - this is the same
                    // state DetailsSources' own badge calls DISCONNECTED: an
                    // origin whose sourceId no longer resolves to an installed
                    // source at all, code-removed rather than merely disabled
                    Card(
                        "Disconnected Sources",
                        systemImage: "cable.connector.slash",
                        detail: "Move a series off a source that's no longer installed"
                    ) { showingDisconnectedMigration = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Import")

                    // no plain "link" + down-arrow glyph exists in SF Symbols
                    // (checked against CoreGlyphs' own name list) - this is
                    // the closest real one: the system's standard "pull data
                    // in from elsewhere" tray, not a document-specific glyph
                    Card(
                        "Restore from Tracker",
                        systemImage: "tray.and.arrow.down",
                        detail: "Rebuild your library from a tracker's list"
                    ) { showingTrackerRestore = true }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Export")
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Migrations")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingSourceMigration) {
            SourceMigrationScreen()
        }
        .navigationDestination(isPresented: $showingDisconnectedMigration) {
            DisconnectedSourceMigrationScreen()
        }
        // a sheet rather than a push: restore is a self-contained process with
        // its own setup step and queue, not a place inside Settings - closing
        // it from the queue, two levels deep, just ends the sheet rather than
        // popping back through setup first
        .sheet(isPresented: $showingTrackerRestore) {
            NavigationStack {
                TrackerRestoreSetupScreen(onFinish: { showingTrackerRestore = false })
            }
            // a swipe-down dismiss sets showingTrackerRestore straight to
            // false, skipping onFinish entirely - which is what the queue
            // screen's own Close asks before ending the session for
            // ("Anything left unsaved won't be added to your library"). the
            // X is the one way out precisely so that warning can never be
            // bypassed by a gesture
            .interactiveDismissDisabled(true)
        }
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

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

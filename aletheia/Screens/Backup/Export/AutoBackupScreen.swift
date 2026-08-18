//
//  AutoBackupScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - no schedule, no background task, no write to
// RecentBackupsScreen's own list yet. exists so Settings > Migrations >
// Auto Backup has somewhere real to go rather than a dead button. when
// built, this is what puts entries in Recent Backups without a reader
// ever opening BackupExportScreen by hand
struct AutoBackupScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("Backing up your library on a schedule isn't built yet.")
        }
        .navigationTitle("Auto Backup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AutoBackupScreen()
    }
}

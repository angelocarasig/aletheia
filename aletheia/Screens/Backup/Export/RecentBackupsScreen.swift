//
//  RecentBackupsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - no storage, no listing, no download logic behind it yet.
// exists so Settings > Migrations > Recent Backups has somewhere real to
// go rather than a dead button. the eventual list is what AutoBackupScreen's
// own schedule would populate, alongside anything BackupExportScreen saved
// by hand
struct RecentBackupsScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Backups Yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Backups you export or that run automatically will show up here, ready to download again.")
        }
        .navigationTitle("Recent Backups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        RecentBackupsScreen()
    }
}

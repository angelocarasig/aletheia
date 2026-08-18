//
//  RecentBackupsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

struct RecentBackupsScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Backups Yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text(
                "Backups you export or that run automatically will show up here, ready to download again."
            )
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

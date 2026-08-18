//
//  BackupExportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - the export side of AletheiaBackupImportScreen. exists so
// Settings > Migrations > Backup Your Library has somewhere real to go
// rather than a dead button
struct BackupExportScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "shippingbox")
        } description: {
            Text("Exporting your library to a backup file isn't built yet.")
        }
        .navigationTitle("Backup Your Library")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        BackupExportScreen()
    }
}

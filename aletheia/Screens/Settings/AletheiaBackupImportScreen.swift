//
//  AletheiaBackupImportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - the import side of whatever Export eventually becomes
// (CLAUDE.md's zlib note: a dependency-free CBZ/backup path already exists,
// nothing uses it yet). exists so Settings > Migrations > From an Aletheia
// Backup has somewhere real to go rather than a dead button
struct AletheiaBackupImportScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "shippingbox")
        } description: {
            Text("Restoring from your own exported backup isn't built yet.")
        }
        .navigationTitle("From an Aletheia Backup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AletheiaBackupImportScreen()
    }
}

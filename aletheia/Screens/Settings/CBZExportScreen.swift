//
//  CBZExportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - a raw chapter archive export, distinct from
// BackupExportScreen's library/metadata backup. CLAUDE.md's zlib note is
// what this is for: zlib is available without a dependency in the iOS 26.2
// SDK, so a dependency-free CBZ writer is possible whenever this gets
// built. exists so Settings > Migrations > Export as CBZ has somewhere real
// to go rather than a dead button
struct CBZExportScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "doc.zipper")
        } description: {
            Text("Exporting chapters as CBZ archives isn't built yet.")
        }
        .navigationTitle("Export as CBZ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        CBZExportScreen()
    }
}

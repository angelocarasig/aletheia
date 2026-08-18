//
//  SourceMigrationScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - moving a series from one source to another has no logic
// behind it yet. exists so Settings > Migrations > Migrate Sources has
// somewhere real to go rather than a dead button
struct SourceMigrationScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "arrow.left.arrow.right")
        } description: {
            Text("Moving a series from one source to another isn't built yet.")
        }
        .navigationTitle("Migrate Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        SourceMigrationScreen()
    }
}

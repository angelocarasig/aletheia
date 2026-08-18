//
//  DisconnectedSourceMigrationScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - moving a series off a source that no longer resolves to an
// installed provider (DetailsSources' own DISCONNECTED state) has no logic
// behind it yet. exists so Settings > Migrations > Disconnected Sources has
// somewhere real to go rather than a dead button
struct DisconnectedSourceMigrationScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "cable.connector.slash")
        } description: {
            Text("Moving a series off a disconnected source isn't built yet.")
        }
        .navigationTitle("Disconnected Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        DisconnectedSourceMigrationScreen()
    }
}

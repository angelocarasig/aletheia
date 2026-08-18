//
//  AutoBackupScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

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

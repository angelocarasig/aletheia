//
//  OtherReaderImportScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// scaffold only - no reader's export format is picked yet (Tachiyomi/Mihon
// backup, Paperback JSON, whatever else eventually). exists so Settings >
// Migrations > From Another Reader has somewhere real to go rather than a
// dead button
struct OtherReaderImportScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "square.and.arrow.down")
        } description: {
            Text(
                "Importing your library from Tachiyomi, Mihon, or another reader's export isn't built yet."
            )
        }
        .navigationTitle("From Another Reader")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        OtherReaderImportScreen()
    }
}

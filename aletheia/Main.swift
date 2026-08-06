//
//  Main.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import SwiftUI

@main
struct AletheiaApp: App {
    // nothing runs in init - the app value is built on the main actor before the
    // first frame, which is exactly where database work must not happen
    @State private var bootstrap = Bootstrap()

    var body: some Scene {
        WindowGroup {
            Group {
                if let compositor = bootstrap.compositor {
                    Tabs
                        .environment(\.compositor, compositor)
                        .environment(\.database, compositor.database)
                } else {
                    BootstrapScreen(phase: bootstrap.phase) {
                        Task { await bootstrap.run() }
                    }
                }
            }
            .task { await bootstrap.run() }
        }
    }

    private var Tabs: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeScreen() }
            Tab("Library", systemImage: "books.vertical") { LibraryScreen() }
            Tab("Search", systemImage: "magnifyingglass") { SearchScreen() }
            Tab("Sources", systemImage: "plus.square.dashed") { SourcesScreen() }
            Tab("Activity", systemImage: "arrow.triangle.2.circlepath") { ActivityScreen() }
        }
    }
}

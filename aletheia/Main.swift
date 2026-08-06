//
//  Main.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import SwiftUI

@main
struct AletheiaApp: App {
    // static, so it is built on first access rather than with the app value. a
    // canvas runs this init but never the scene below, so a preview never
    // touches it - and therefore never stands up the database for a view that
    // has no use for it
    private static let compositor = Compositor()

    init() {
        guard !Constants.App.isPreview else { return }

        Self.compositor.registry.seed()
        Self.compositor.db.clean()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Home", systemImage: "house") { HomeScreen() }
                Tab("Library", systemImage: "books.vertical") { LibraryScreen() }
                Tab("Search", systemImage: "magnifyingglass") { SearchScreen() }
                Tab("Sources", systemImage: "plus.square.dashed") { SourcesScreen() }
                Tab("Activity", systemImage: "arrow.triangle.2.circlepath") { ActivityScreen() }
            }
            .environment(\.compositor, Self.compositor)
            .environment(\.database, .client)
        }
    }
}

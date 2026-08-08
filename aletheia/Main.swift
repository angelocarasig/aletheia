//
//  Main.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import SwiftUI

enum AppTab: Hashable {
    case home, library, search, sources, activity
}

@main
struct AletheiaApp: App {
    // nothing runs in init - the app value is built on the main actor before the
    // first frame, which is exactly where database work must not happen
    @State private var bootstrap = Bootstrap()
    @State private var tab: AppTab = .home
    @State private var retaps: [AppTab: Int] = [:]

    // a plain selection binding never reports taps on the already-active tab,
    // so the setter counts them and screens reset off their tab's counter
    private var selection: Binding<AppTab> {
        Binding {
            tab
        } set: { newValue in
            if newValue == tab { retaps[newValue, default: 0] += 1 }
            if newValue == .sources { bootstrap.bypass.registerTap() }
            tab = newValue
        }
    }

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
        TabView(selection: selection) {
            Tab("Home", systemImage: "house", value: .home) { HomeScreen() }
            Tab("Library", systemImage: "books.vertical", value: .library) { LibraryScreen() }
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchScreen(reset: retaps[.search, default: 0])
            }
            Tab("Sources", systemImage: "plus.square.dashed", value: .sources) { SourcesScreen() }
            Tab("Activity", systemImage: "arrow.triangle.2.circlepath", value: .activity) { ActivityScreen() }
        }
    }
}

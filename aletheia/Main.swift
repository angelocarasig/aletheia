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

// the one thing that has to happen during launch rather than during a frame:
// a launch the system starts for a scheduled task connects no window, and
// registering after launch ends is fatal rather than late
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Launch.registerScheduledRefresh()
        return true
    }
}

@main
struct AletheiaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // nothing runs in init - the app value is built on the main actor before the
    // first frame, which is exactly where database work must not happen
    @Environment(\.scenePhase) private var scenePhase

    // the one exception, and it does no work: it starts the drain that empties
    // the log's intake buffer. anything logged before this - bootstrap included -
    // is held by the unbounded buffer rather than lost, so the cost of being
    // early is nothing and the cost of being late is the first launch's lines
    init() {
        AppLog.shared.start()
    }

    @State private var bootstrap = Bootstrap()
    @State private var router = Router()
    @State private var retaps: [AppTab: Int] = [:]

    // a plain selection binding never reports taps on the already-active tab,
    // so the setter counts them and screens reset off their tab's counter
    private var selection: Binding<AppTab> {
        Binding {
            router.tab
        } set: { newValue in
            if newValue == router.tab { retaps[newValue, default: 0] += 1 }
            if newValue == .sources { bootstrap.bypass.registerTap() }
            router.tab = newValue
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let compositor = bootstrap.compositor {
                    Tabs
                        .environment(\.compositor, compositor)
                        .environment(\.database, compositor.database)
                        .environment(\.router, router)
                        .authChallenge(from: compositor.presenter)
                } else {
                    BootstrapScreen(phase: bootstrap.phase) {
                        Task { await bootstrap.run() }
                    }
                }
            }
            .task { await bootstrap.run() }
            // the half of the schedule nothing can silently switch off: coming
            // back to the app is when a missed automatic run is noticed
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    bootstrap.compositor?.refresh.catchUp()

                default:
                    break
                }
            }
        }
    }

    private var Tabs: some View {
        TabView(selection: selection) {
            Tab("Home", systemImage: "house", value: .home) { HomeScreen() }
            Tab("Library", systemImage: "books.vertical", value: .library) { LibraryScreen() }
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchScreen(reset: retaps[.search, default: 0], seed: router.search)
            }
            Tab("Sources", systemImage: "plus.square.dashed", value: .sources) { SourcesScreen() }
            Tab("Activity", systemImage: "arrow.triangle.2.circlepath", value: .activity) { ActivityScreen() }
        }
    }
}

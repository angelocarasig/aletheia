//
//  RefreshSettingsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

// what a library refresh checks, and whether it ever runs on its own. both
// default to the least surprising thing: check everything, run only when asked.
// see docs/features/background-activity.md 4.7
struct RefreshSettingsScreen: View {
    @AppStorage(Preferences.Key.refreshInterval)
    private var interval = Preferences.Default.refreshInterval

    @AppStorage(Preferences.Key.refreshSkipCompleted)
    private var skipCompleted = Preferences.Default.refreshSkipCompleted

    @AppStorage(Preferences.Key.refreshSkipUnread)
    private var skipUnread = Preferences.Default.refreshSkipUnread

    @AppStorage(Preferences.Key.refreshSkipNotStarted)
    private var skipNotStarted = Preferences.Default.refreshSkipNotStarted

    @Environment(\.compositor) private var compositor

    @State private var refreshStatus: UIBackgroundRefreshStatus = .available

    private enum Interval: Int, CaseIterable, Identifiable {
        case never = 0
        case sixHours = 6
        case twelveHours = 12
        case daily = 24
        case weekly = 168

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .never: "Never"
            case .sixHours: "Every 6 Hours"
            case .twelveHours: "Every 12 Hours"
            case .daily: "Daily"
            case .weekly: "Weekly"
            }
        }
    }

    var body: some View {
        Form {
            if showsRefreshDisabled {
                Section {
                    Banner(
                        "Background App Refresh is off",
                        message: "Turn it on in Settings > General > Background App Refresh, or your library is only checked when you open the app.",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        action: openSettings
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker("Check Automatically", selection: $interval) {
                    ForEach(Interval.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
            } header: {
                Text("Automatic")
            } footer: {
                // said plainly because the alternative is a user concluding the
                // setting is broken. iOS decides when, and sometimes decides not
                // to at all - the app checks again on opening for exactly that
                Text(interval == 0
                     ? "Your library is only checked when you pull to refresh."
                     : "iOS chooses when to run this, so it may be later than the interval. If it never runs, the check happens next time you open the app.")
            }

            Section {
                Toggle("Skip Finished Series", isOn: $skipCompleted)
                Toggle("Skip Series With Unread Chapters", isOn: $skipUnread)
                Toggle("Skip Series You Haven't Started", isOn: $skipNotStarted)
            } header: {
                Text("What to Check")
            } footer: {
                Text(footer)
            }

            #if DEBUG
            // a scheduled run cannot be triggered on demand and cannot be
            // observed from the simulator, so this fakes the launch ios will not
            // make. it used to fire automatically on every backgrounding, which
            // is how it was verified once and then how it refreshed the whole
            // library every time the screen locked - a harness that runs without
            // being asked is indistinguishable from the bug it was built to find
            Section {
                Button("Rehearse a Scheduled Run") {
                    Task { await compositor.refresh.rehearse() }
                }
                .disabled(interval == 0)
            } header: {
                Text("Debug")
            } footer: {
                Text(interval == 0
                     ? "Turn automatic checks on to rehearse one."
                     : "Arms the request, then fakes the launch after five seconds. Lock the screen now to watch it run under real conditions.")
            }
            #endif
        }
        .navigationTitle("Library Updates")
        .navigationBarTitleDisplayMode(.inline)
        // the request carries the interval, so changing it has to re-arm rather
        // than wait for the next run to notice
        .onChange(of: interval) { _, new in
            compositor.refresh.schedule()

            // asked here rather than at launch: the notification only exists for
            // a run nobody watched, so the request has nothing to explain itself
            // with until someone has asked for those runs
            guard new > 0 else { return }
            Task { await Notifier.promote() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.backgroundRefreshStatusDidChangeNotification
        )) { _ in
            refreshStatus = UIApplication.shared.backgroundRefreshStatus
        }
        .onAppear { refreshStatus = UIApplication.shared.backgroundRefreshStatus }
    }

    // only when the setting is asking for something the system is refusing, and
    // never when restricted: that reader is under parental controls or a managed
    // profile and has no way to act on it, so apple's own guidance is not to say
    // anything. denied cannot say whether this app or the whole system is off,
    // which is why the copy names the path rather than the switch
    private var showsRefreshDisabled: Bool {
        interval > 0 && refreshStatus == .denied
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // one sentence per switch, because "skip finished" reads obvious and is not:
    // the status comes from the source and only updates when the series is
    // opened, so it can be wrong in the direction that skips something live
    private var footer: String {
        var lines: [String] = []

        if skipCompleted {
            lines.append("Finished series are skipped. Their status updates only when you open them, so a series that has resumed may be missed until then.")
        }
        if skipUnread {
            lines.append("Series with chapters you haven't read yet are skipped.")
        }
        if skipNotStarted {
            lines.append("Series you've never opened are skipped.")
        }

        return lines.isEmpty
            ? "Every series in your library is checked."
            : lines.joined(separator: "\n\n")
    }
}

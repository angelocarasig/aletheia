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
        }
        .navigationTitle("Library Updates")
        .navigationBarTitleDisplayMode(.inline)
        // the request carries the interval, so changing it has to re-arm rather
        // than wait for the next run to notice
        .onChange(of: interval) { _, _ in
            compositor.refresh.schedule()
        }
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

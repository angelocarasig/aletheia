//
//  RefreshSettingsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import BackgroundTasks
import SwiftUI

struct RefreshSettingsScreen: View {
    @AppStorage(Preferences.Key.refreshAutomatic)
    private var automatic = Preferences.Default.refreshAutomatic

    @AppStorage(Preferences.Key.refreshSkipCompleted)
    private var skipCompleted = Preferences.Default.refreshSkipCompleted

    @AppStorage(Preferences.Key.refreshSkipUnread)
    private var skipUnread = Preferences.Default.refreshSkipUnread

    @AppStorage(Preferences.Key.refreshSkipNotStarted)
    private var skipNotStarted = Preferences.Default.refreshSkipNotStarted

    @Environment(\.compositor) private var compositor
    @Environment(\.scenePhase) private var scenePhase

    @State private var refreshStatus: UIBackgroundRefreshStatus = .available

    #if DEBUG
        @State private var armed: Armed = .none

        // no-earliest-date is a distinct armed state, not a missing one - self-clearing, since the run
        // that consumes it re-arms with a date, so this never claims a spent request
        private enum Armed: Equatable {
            case none
            case soon
            case at(Date)
        }
    #endif

    var body: some View {
        Form {
            if showsRefreshDisabled {
                Section {
                    Banner(
                        "Background App Refresh is off",
                        message:
                            "Turn it on in Settings > General > Background App Refresh, or your library is only checked when you open the app.",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        action: openSettings
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Toggle("Check Automatically", isOn: $automatic)
            } header: {
                Text("Automatic")
            } footer: {
                Text(
                    automatic
                        ? "iOS chooses when this runs, usually while the device is idle and charging overnight. If it never runs, the check happens next time you open the app."
                        : "Your library is only checked when you pull to refresh.")
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
                // reads the scheduler's pending request, not the setting - deriving a state from the setting
                // alone would claim a run that four separate conditions can still prevent
                Section {
                    Toggle("Run at the Next Opportunity", isOn: asap)
                        .disabled(!automatic)
                        .sensoryFeedback(.selection, trigger: armed)
                } header: {
                    Text("Debug")
                } footer: {
                    Text(scheduleFooter)
                }
            #endif
        }
        #if DEBUG
            .task { armed = await pendingRun() }
            .onChange(of: compositor.refresh.isRunning) { _, running in
                guard !running else { return }
                Task { armed = await pendingRun() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { armed = await pendingRun() }
            }
        #endif
        .navigationTitle("Library Updates")
        .navigationBarTitleDisplayMode(.inline)
        // schedule() is called unconditionally - turning off must actively withdraw the pending request
        .onChange(of: automatic) { _, on in
            compositor.refresh.schedule()

            #if DEBUG
                Task { armed = await pendingRun() }
            #endif

            guard on else { return }
            Task { await Notifier.promote() }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.backgroundRefreshStatusDidChangeNotification
            )
        ) { _ in
            refreshStatus = UIApplication.shared.backgroundRefreshStatus
        }
        .onAppear { refreshStatus = UIApplication.shared.backgroundRefreshStatus }
    }

    // excludes .restricted deliberately - that reader is under parental/managed controls with no way to
    // act on it, and Apple's guidance is not to surface it
    private var showsRefreshDisabled: Bool {
        automatic && refreshStatus == .denied
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    #if DEBUG
        // reads the scheduler's state back, not the tap - there is no "cancel everything" position, that's the setting above
        private var asap: Binding<Bool> {
            Binding(
                get: { armed == .soon },
                set: { on in
                    compositor.refresh.schedule(asap: on)
                    Task { armed = await pendingRun() }
                }
            )
        }

        private func pendingRun() async -> Armed {
            let request = await BGTaskScheduler.shared.pendingTaskRequests()
                .first { $0.identifier == Constants.Tasks.scheduledRefresh }

            guard let request else { return .none }
            guard let earliest = request.earliestBeginDate else { return .soon }
            return .at(earliest)
        }

        private var scheduleFooter: String {
            guard automatic else { return "Turn automatic checks on to schedule one." }

            #if targetEnvironment(simulator)
                return
                    "The simulator never accepts a scheduled request, so nothing is armed here. Run this on a device."
            #else
                switch armed {
                case .none:
                    return "No run is armed."
                case .soon:
                    return
                        "Armed with no waiting period. iOS still picks the moment, and in practice that means while the device is idle and charging. This clears itself once a run takes it."
                case .at(let date):
                    return
                        "A run is armed for \(date.formatted(date: .abbreviated, time: .shortened)) at the earliest. Turn this on to drop that wait."
                }
            #endif
        }
    #endif

    private var footer: String {
        var lines: [String] = []

        if skipCompleted {
            lines.append(
                "Finished series are skipped. Their status updates only when you open them, so a series that has resumed may be missed until then."
            )
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

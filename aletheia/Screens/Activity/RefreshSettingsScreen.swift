//
//  RefreshSettingsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import BackgroundTasks
import SwiftUI

// what a library refresh checks, and whether it ever runs on its own. both
// default to the least surprising thing: check everything, run only when asked.
// see docs/features/background-activity.md 4.7
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

        // a request with no earliest date is a third state, not a missing one: it is
        // armed and carries no floor, which is the whole point of the toggle. it is
        // also self-clearing - the run that takes it re-arms with a date, so the
        // toggle falls back to off on its own rather than claiming a spent request
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
                // on or off, never a cadence: ios runs a processing task when the
                // device is idle and charging, so a chosen interval would be a
                // promise made by the wrong party. said plainly because the
                // alternative is a reader concluding the setting is broken
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
                // nothing can make ios launch the task now, so the offer is to drop
                // the twelve-hour floor and let the next natural opportunity take it.
                // the pending request is what this reads - anything derived from the
                // setting would state a run four separate conditions can prevent
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
            // a finished run re-arms behind the floor again, so the toggle is stale
            // the moment the walk ends and stale again on every return to the screen
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
        // turning it off has to withdraw the pending request rather than wait for
        // the next run to notice nobody wants one
        .onChange(of: automatic) { _, on in
            compositor.refresh.schedule()

            #if DEBUG
                Task { armed = await pendingRun() }
            #endif

            // asked here rather than at launch: the notification only exists for
            // a run nobody watched, so the request has nothing to explain itself
            // with until someone has asked for those runs
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

    // only when the setting is asking for something the system is refusing, and
    // never when restricted: that reader is under parental controls or a managed
    // profile and has no way to act on it, so apple's own guidance is not to say
    // anything. denied cannot say whether this app or the whole system is off,
    // which is why the copy names the path rather than the switch
    private var showsRefreshDisabled: Bool {
        automatic && refreshStatus == .denied
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    #if DEBUG
        // the toggle writes a request and reads the answer back, so what it shows is
        // the scheduler's state rather than the tap's. turning it off restores the
        // ordinary floor - there is no third position for "cancel everything", since
        // that is what the setting above is for
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
                    // said plainly because the toggle reads like a trigger and is not.
                    // the honest expectation is apple's own: idle and charging, usually
                    // overnight, within about two days
                    return
                        "Armed with no waiting period. iOS still picks the moment, and in practice that means while the device is idle and charging. This clears itself once a run takes it."
                case .at(let date):
                    return
                        "A run is armed for \(date.formatted(date: .abbreviated, time: .shortened)) at the earliest. Turn this on to drop that wait."
                }
            #endif
        }
    #endif

    // one sentence per switch, because "skip finished" reads obvious and is not:
    // the status comes from the source and only updates when the series is
    // opened, so it can be wrong in the direction that skips something live
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

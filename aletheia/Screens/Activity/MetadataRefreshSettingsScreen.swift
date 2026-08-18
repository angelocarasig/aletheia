//
//  MetadataRefreshSettingsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import BackgroundTasks
import SwiftUI

// unlike RefreshSettingsScreen this is a real cadence choice, not an on/off
// toggle - metadata does not change often enough to justify daily checking
// the way chapters do, so the control offers the actual options rather than
// hiding behind a switch. see docs/features/metadata-refresh.md
struct MetadataRefreshSettingsScreen: View {
    @AppStorage(Preferences.Key.metadataRefreshInterval)
    private var interval: MetadataRefreshInterval = Preferences.Default.metadataRefreshInterval

    @AppStorage(Preferences.Key.metadataSkipCompleted)
    private var skipCompleted = Preferences.Default.metadataSkipCompleted

    @AppStorage(Preferences.Key.metadataSkipUnread)
    private var skipUnread = Preferences.Default.metadataSkipUnread

    @AppStorage(Preferences.Key.metadataSkipNotStarted)
    private var skipNotStarted = Preferences.Default.metadataSkipNotStarted

    @Environment(\.compositor) private var compositor
    @Environment(\.scenePhase) private var scenePhase

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
            Section {
                Picker("Check Every", selection: $interval) {
                    ForEach(MetadataRefreshInterval.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Automatic")
            } footer: {
                Text(footer)
            }

            Section {
                Toggle("Skip Finished Series", isOn: $skipCompleted)
                Toggle("Skip Series With Unread Chapters", isOn: $skipUnread)
                Toggle("Skip Series You Haven't Started", isOn: $skipNotStarted)
            } header: {
                Text("What to Check")
            } footer: {
                Text(skipFooter)
            }

            #if DEBUG
                // nothing can make ios launch the task now, so the offer is to drop
                // the floor and let the next natural opportunity take it. the
                // pending request is what this reads - anything derived from the
                // setting would state a run four separate conditions can prevent
                Section {
                    Toggle("Run at the Next Opportunity", isOn: asap)
                        .disabled(interval == .off)
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
            .onChange(of: compositor.metadata.isRunning) { _, running in
                guard !running else { return }
                Task { armed = await pendingRun() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { armed = await pendingRun() }
            }
        #endif
        .navigationTitle("Metadata Updates")
        .navigationBarTitleDisplayMode(.inline)
        // the toggle writes a preference; the schedule has to be told
        // explicitly, same as RefreshSettingsScreen does for its own toggle
        .onChange(of: interval) { _, _ in
            compositor.metadata.schedule()

            #if DEBUG
                Task { armed = await pendingRun() }
            #endif
        }
    }

    private var footer: String {
        interval == .off
            ? "Series details are only refreshed from the Details screen itself."
            : "iOS chooses when this runs, usually while the device is idle and charging. Synopses, ratings and publication status don't change often, so this checks far less frequently than new chapters do."
    }

    // one sentence per switch, same reasoning RefreshSettingsScreen.footer
    // gives: "skip finished" reads obvious and is not, since the status only
    // updates when the series is opened
    private var skipFooter: String {
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

    #if DEBUG
        // the toggle writes a request and reads the answer back, so what it shows is
        // the scheduler's state rather than the tap's. turning it off restores the
        // ordinary floor - there is no third position for "cancel everything", since
        // that is what the picker above is for
        private var asap: Binding<Bool> {
            Binding(
                get: { armed == .soon },
                set: { on in
                    compositor.metadata.schedule(asap: on)
                    Task { armed = await pendingRun() }
                }
            )
        }

        private func pendingRun() async -> Armed {
            let request = await BGTaskScheduler.shared.pendingTaskRequests()
                .first { $0.identifier == Constants.Tasks.scheduledMetadataRefresh }

            guard let request else { return .none }
            guard let earliest = request.earliestBeginDate else { return .soon }
            return .at(earliest)
        }

        private var scheduleFooter: String {
            guard interval != .off else { return "Turn automatic checks on to schedule one." }

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
}

// MARK: - Previews

#Preview {
    NavigationStack {
        MetadataRefreshSettingsScreen()
    }
}

//
//  Notifier.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import UserNotifications

// notifies only about a refresh that finished while nobody was watching, not
// progress - both iOS precedents post only when backgrounded.
// see docs/features/background-activity.md 2
enum Notifier {
    // provisional, so nothing ever interrupts to ask - these arrive quietly
    // in notification centre until the user promotes them
    static func prepare() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .provisional])
    }

    // asked at the moment it makes sense - turning on automatic checks is the
    // reader saying they want the app working while they're away, the only
    // moment this prompt explains itself
    static func promote() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        // authorized already delivers properly, denied is permanent - asking
        // again does nothing in either case, and iOS shows no prompt
        guard status == .provisional || status == .notDetermined else { return }

        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func refreshed(
        added: Int, series: Int, checked: Int, failures: Int, skipped: Int
    ) async {
        let content = UNMutableNotificationContent()

        if added > 0 {
            content.title = "New Chapters"
            content.body =
                series == 1
                ? "\(added) new \(added == 1 ? "chapter" : "chapters") in one series."
                : "\(added) new \(added == 1 ? "chapter" : "chapters") across \(series) series."
            content.sound = .default
        } else {
            content.title = "Library Checked"
            content.body =
                checked == 1
                ? "No new chapters in one series."
                : "No new chapters in \(checked) series."
            // no sound - nothing arriving is not worth a noise
        }

        // fully excluded by a skip rule, not merely thinned an origin off of -
        // see Compositor.Refresh.Skips
        if skipped > 0 {
            content.body +=
                skipped == 1
                ? " One series skipped."
                : " \(skipped) series skipped."
        }

        if failures > 0 {
            content.body +=
                failures == 1
                ? " One source couldn't be reached."
                : " \(failures) sources couldn't be reached."
        }

        // stable identifier so each run replaces the last rather than stacking
        let request = UNNotificationRequest(
            identifier: "refresh.result",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // "updated" rather than "added" - there is no count of new things, only
    // of suppliers that answered with something different from what was stored
    static func metadataRefreshed(updated: Int, series: Int, failures: Int) async {
        let content = UNMutableNotificationContent()

        if updated > 0 {
            content.title = "Metadata Updated"
            content.body =
                series == 1
                ? "One series' details were refreshed."
                : "\(updated) of \(series) series had updated details."
        } else {
            content.title = "Metadata Checked"
            content.body =
                series == 1
                ? "One series' details are up to date."
                : "\(series) series' details are up to date."
        }

        if failures > 0 {
            content.body +=
                failures == 1
                ? " One source couldn't be reached."
                : " \(failures) sources couldn't be reached."
        }

        let request = UNNotificationRequest(
            identifier: "metadata.result",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

//
//  Notifier.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation
import UserNotifications

// the one thing this app notifies about: a refresh that finished while nobody
// was watching it found something. progress stays in the app - a run you can see
// is already telling that story, and both iOS precedents post only when
// backgrounded. see docs/features/background-activity.md 2
enum Notifier {
    // provisional, so nothing ever interrupts to ask. these arrive quietly in
    // notification centre and the user promotes them if they want them louder,
    // which is the honest trade for a permission we cannot justify prompting for
    // before the feature has ever proved useful
    static func prepare() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .provisional])
    }

    // the same permission, asked at the moment it makes sense. provisional costs
    // nothing and is worth almost as little - it arrives with no banner and no
    // sound, so the one notification this app sends lands where nobody is
    // looking. turning on automatic checks is the reader saying they want the
    // app working while they are away, which is the only moment the prompt
    // explains itself
    static func promote() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        // authorized already delivers properly, and denied is permanent - asking
        // again does nothing in either case, and iOS shows no prompt
        guard status == .provisional || status == .notDetermined else { return }

        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func refreshed(added: Int, series: Int, checked: Int, failures: Int) async {
        let content = UNMutableNotificationContent()

        if added > 0 {
            content.title = "New Chapters"
            content.body =
                series == 1
                ? "\(added) new \(added == 1 ? "chapter" : "chapters") in one series."
                : "\(added) new \(added == 1 ? "chapter" : "chapters") across \(series) series."
            content.sound = .default
        } else {
            // the count is what makes this a result rather than a shrug: it says
            // the walk happened and how much of the library it got through, which
            // is the question a reader actually has when nothing arrived
            content.title = "Library Checked"
            content.body =
                checked == 1
                ? "No new chapters in one series."
                : "No new chapters in \(checked) series."
            // no sound: it stays in notification centre until dealt with, but
            // nothing arriving is not worth a noise
        }

        if failures > 0 {
            content.body +=
                failures == 1
                ? " One source couldn't be reached."
                : " \(failures) sources couldn't be reached."
        }

        // nil trigger fires immediately. the identifier is stable so each run
        // replaces the last rather than stacking - one entry that always reads
        // as the current state of the library, staying put until dismissed
        let request = UNNotificationRequest(
            identifier: "refresh.result",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // metadata's own version of refreshed(...) - same shape, same
    // background-only gate, its own stable identifier so a run replaces the
    // last rather than stacking. "updated" rather than "added": there is no
    // count of new things, only of suppliers that answered with something
    // different from what was already stored
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

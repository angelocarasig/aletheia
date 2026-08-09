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

    static func newChapters(_ count: Int, series: Int) async {
        guard count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "New Chapters"
        content.body = series == 1
            ? "\(count) new \(count == 1 ? "chapter" : "chapters") in one series."
            : "\(count) new \(count == 1 ? "chapter" : "chapters") across \(series) series."
        content.sound = .default

        // nil trigger fires immediately; the identifier is stable so a second
        // run replaces the first rather than stacking
        let request = UNNotificationRequest(
            identifier: "refresh.newChapters",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

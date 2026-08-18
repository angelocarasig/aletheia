//
//  LiveRelativeText.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct LiveRelativeText: View {
    let date: Date

    var body: some View {
        LiveRelative(date: date) { text in
            Text(text)
                .contentTransition(.numericText())
                .animation(.default, value: text)
        }
    }

    fileprivate static func format(_ date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// hands the caller the formatted string rather than a Text, so it can be
// embedded inside a larger sentence that still wraps as one Text
struct LiveRelative<Content: View>: View {
    let date: Date
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(LiveRelativeText.format(date, relativeTo: context.date))
        }
    }
}

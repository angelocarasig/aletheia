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

// the same clock, for a stamp that lives inside a sentence rather than beside
// one. an HStack cannot be used there: the sentence has to stay a single Text
// or it loses the ability to wrap, so the caller is handed the string and
// builds its own line
struct LiveRelative<Content: View>: View {
    let date: Date
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(LiveRelativeText.format(date, relativeTo: context.date))
        }
    }
}

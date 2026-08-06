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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let text = Self.format(date, relativeTo: context.date)
            Text(text)
                .contentTransition(.numericText())
                .animation(.default, value: text)
        }
    }

    private static func format(_ date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

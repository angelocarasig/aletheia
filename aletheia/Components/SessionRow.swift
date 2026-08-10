//
//  SessionRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI
import Tagged

// a sitting, told the same way wherever it appears
// the destination is the caller's to declare, not a value pushed at the stack:
// this row appears on screens presented with navigationDestination(isPresented:),
// where a value push lands UNDER the screen doing the pushing and only surfaces
// once it is popped
struct SessionRow: View {
    let session: ReadingSessionEntry
    let open: (SeriesEntry) -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let fillOpacity = 0.05
    }

    var body: some View {
        // a dead snapshot still names what happened; it just cannot go anywhere
        if session.alive {
            Row
                .contentShape(.rect)
                .tappable { open(.library(SeriesRecord.ID(rawValue: session.seriesId))) }
        } else {
            Row
        }
    }

    private var Row: some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(session.seriesTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(session.alive ? .primary : .secondary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: dimensions.spacing.space2) {
                // always rendered, including under a minute. omitting it left
                // some rows one line and some two, which broke the baseline the
                // clock column is scanned down - and a blank read as missing
                // data rather than as a short sitting
                Text(ReadingFormat.duration(session.seconds))
                    .font(.subheadline)
                    .foregroundStyle(session.seconds >= 60 ? .primary : .secondary)

                Text(session.startedDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    private var summary: String {
        var parts: [String] = []
        if session.chaptersRead > 0 {
            parts.append("\(session.chaptersRead) finished")
        }
        if session.pagesRead > 0 {
            parts.append("\(session.pagesRead) pages")
        }
        return parts.isEmpty ? "Read" : parts.joined(separator: " · ")
    }
}

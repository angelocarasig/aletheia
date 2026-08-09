//
//  SessionRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI
import Tagged

// a sitting, told the same way wherever it appears
struct SessionRow: View {
    let session: ReadingSessionEntry

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let fillOpacity = 0.05
    }

    var body: some View {
        // a dead snapshot still names what happened; it just cannot go anywhere
        if session.alive {
            NavigationLink(value: SeriesEntry.library(SeriesRecord.ID(rawValue: session.seriesId))) {
                Row
            }
            .buttonStyle(.plain)
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
                Text(ReadingFormat.duration(session.seconds))
                    .font(.subheadline)

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

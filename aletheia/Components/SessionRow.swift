//
//  SessionRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI
import Tagged
import Kingfisher

// a sitting, told the same way wherever it appears
// the destination is the caller's to declare, not a value pushed at the stack:
// this row appears on screens presented with navigationDestination(isPresented:),
// where a value push lands UNDER the screen doing the pushing and only surfaces
// once it is popped
struct SessionRow: View {
    let session: ReadingSessionEntry
    let open: (SeriesEntry) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor

    private enum Layout {
        static let fillOpacity = 0.05
        static let placeholderOpacity = 0.1
        // wider than the cover ratio, and deliberately: the height is what sets
        // the row, and a wider window onto the same artwork shows more of it
        // without making the row taller. it CROPS rather than stretches -
        // scaledToFill inside a fixed frame, so the picture keeps its own shape
        // and the frame decides how much of it you see
        static let coverWidth: CGFloat = 58
        static let coverHeight: CGFloat = 70
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

    // artwork, then what and when, then how much. the clock left the trailing
    // column and joined the title: a sitting is a thing that happened at a time,
    // and splitting those across the row made the eye read the row twice. the
    // amounts are the detail of that sentence, so they sit under it
    private var Row: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Cover

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
                    Text(session.seriesTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .foregroundStyle(session.alive ? .primary : .secondary)

                    Spacer(minLength: 0)

                    Text(session.startedDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                }

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    // history is never deleted, so a session outlives the series it names. the
    // placeholder is the honest answer there rather than a missing row
    private var Cover: some View {
        let local = compositor.assets.local(for: session.path)

        return Color.clear
            .frame(width: Layout.coverWidth, height: Layout.coverHeight)
            .overlay {
                if let cover = local ?? session.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder { Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer() }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.primary.opacity(Layout.placeholderOpacity))
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }

    // the duration moved in here from its own column. always rendered, including
    // under a minute: omitting it left some rows saying less than others for no
    // reason a reader could see, and a blank read as missing data rather than as
    // a short sitting
    private var summary: String {
        var parts: [String] = []
        if session.chaptersRead > 0 {
            parts.append("\(session.chaptersRead) finished")
        }
        if session.pagesRead > 0 {
            parts.append("\(session.pagesRead) pages")
        }
        parts.append(ReadingFormat.duration(session.seconds))
        return parts.joined(separator: " · ")
    }
}

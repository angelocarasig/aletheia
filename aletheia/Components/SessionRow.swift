//
//  SessionRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Kingfisher
import SwiftUI
import Tagged

// destination is a caller-supplied closure, not a value-based navigationDestination
// push - this row appears on screens presented via navigationDestination(isPresented:),
// where a value push lands under that screen and only surfaces once it's popped
struct SessionRow: View {
    let session: ReadingSessionEntry
    let open: (SeriesEntry) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor

    private enum Layout {
        static let fillOpacity = 0.05
        static let placeholderOpacity = 0.1
        static let coverWidth: CGFloat = 58
        static let coverHeight: CGFloat = 70
    }

    var body: some View {
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
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    // reading_session rows outlive a deleted series, so cover may have no
    // local asset or series-backed url to resolve
    private var Cover: some View {
        let local = compositor.assets.local(for: session.path)

        return Color.clear
            .frame(width: Layout.coverWidth, height: Layout.coverHeight)
            .overlay {
                if let cover = local ?? session.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer()
                        }
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

    // duration is always appended, even near zero - omitting it read as
    // missing data rather than a short sitting
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

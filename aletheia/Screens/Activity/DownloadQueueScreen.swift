//
//  DownloadQueueScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI
import Tagged

struct DownloadQueueScreen: View {
    let downloads: Compositor.Downloads

    @Environment(\.dimensions) private var dimensions
    @State private var expanded = false

    private enum Layout {
        static let fillOpacity = 0.05
        static let tick: TimeInterval = 0.2
        static let collapsedLimit = 5
        static let barHeight: CGFloat = 8
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                if downloads.order.isEmpty {
                    ContentUnavailableView(
                        "Queue Is Empty",
                        systemImage: "arrow.down.circle",
                        description: Text(
                            "Chapters you download will appear here while they're being saved.")
                    )
                } else {
                    QueueSection
                }

                DownloadStorageSection()
            }
            .padding(.horizontal, dimensions.spacing.space16)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !downloads.order.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel All", role: .destructive) {
                        downloads.cancelAll()
                    }
                }
            }
        }
        .animation(.settle, value: downloads.order.count)
        .animation(.settle, value: expanded)
    }
}

// MARK: - Queue

extension DownloadQueueScreen {
    fileprivate var QueueSection: some View {
        VStack(spacing: dimensions.spacing.space8) {
            Summary

            ForEach(visibleDownloads) { download in
                Row(download)
            }

            if downloads.order.count > Layout.collapsedLimit {
                ExpandToggle
            }
        }
    }

    private var visibleDownloads: [Download] {
        expanded ? downloads.order : Array(downloads.order.prefix(Layout.collapsedLimit))
    }

    fileprivate var ExpandToggle: some View {
        let remaining = downloads.order.count - Layout.collapsedLimit

        return HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .contentTransition(.symbolEffect(.replace))

            Text(expanded ? "Hide" : "Show ^[\(remaining) More Chapter](inflect: true)")
        }
        .font(.subheadline)
        .foregroundStyle(.brand)
        .frame(maxWidth: .infinity)
        .padding(dimensions.spacing.space12)
        .background(
            Palette.brand.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius8)
        )
        .tappable {
            withAnimation { expanded.toggle() }
        }
    }
}

// MARK: - Rows

extension DownloadQueueScreen {
    // coarse counters, not a fold over `order` - summing every item's progress would
    // put this view back on the ten-times-a-second path the per-item split exists to avoid
    fileprivate var Summary: some View {
        let completed = downloads.completed
        let total = downloads.total
        let fraction = total > 0 ? Double(completed) / Double(total) : 0

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space4) {
                Text("\(completed)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(completed)))

                Text("of \(total) chapters")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy(duration: Layout.tick), value: completed)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(Layout.fillOpacity))

                    Capsule()
                        .fill(.brand)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: Layout.barHeight)
            .animation(.snappy, value: fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    fileprivate func Row(_ download: Download) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(download.series)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(download.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Status(download)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: dimensions.spacing.space12) {
                if download.isFailed {
                    Button {
                        // resolves and re-admits - enqueue already treats an
                        // id already in index as a retry, not a duplicate
                        downloads.enqueue(chapter: download.id)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry download")
                }

                Button {
                    downloads.cancel(chapter: download.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from queue")
            }
        }
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    @ViewBuilder
    fileprivate func Status(_ download: Download) -> some View {
        switch download.state {
        case .queued:
            Text("Waiting")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        case .preparing:
            Text("Preparing")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        case .downloading:
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                ProgressView(value: download.fraction)
                    .tint(.brand)

                // animated here, not at the write site - the downloader's writes carry no animation of their own
                Text("\(download.pagesDone) of \(download.pagesTotal) pages")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(download.pagesDone)))
                    .animation(.snappy(duration: Layout.tick), value: download.pagesDone)
            }
            .padding(.top, dimensions.spacing.space2)

        case .failed(let reason):
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.danger)
                .lineLimit(2)
        }
    }
}

// MARK: - Previews

#Preview("In Progress") {
    let downloading = Download(
        id: ChapterRecord.ID(rawValue: 1), title: "Chapter 42", series: "Solo Leveling")
    downloading.advance(12, of: 24)

    let preparing = Download(
        id: ChapterRecord.ID(rawValue: 2), title: "Chapter 88", series: "Omniscient Reader")
    preparing.prepare()

    let queuedA = Download(
        id: ChapterRecord.ID(rawValue: 3), title: "Chapter 43", series: "Solo Leveling")
    let queuedB = Download(
        id: ChapterRecord.ID(rawValue: 4), title: "Chapter 210", series: "Berserk")

    let failed = Download(
        id: ChapterRecord.ID(rawValue: 5), title: "Chapter 5", series: "Vagabond")
    failed.fail("Connection timed out.")

    return NavigationStack {
        DownloadQueueScreen(
            downloads: .preview(
                order: [downloading, preparing, queuedA, queuedB, failed],
                completed: 2,
                total: 7
            )
        )
    }
}

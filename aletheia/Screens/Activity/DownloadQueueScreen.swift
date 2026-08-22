//
//  DownloadQueueScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

struct DownloadQueueScreen: View {
    let downloads: Compositor.Downloads

    @Environment(\.dimensions) private var dimensions
    @State private var expanded = false

    private enum Layout {
        static let fillOpacity = 0.05
        static let tick: TimeInterval = 0.2
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
    // collapsed to just the summary by default - storage-by-size below is the
    // primary content of this screen now, the live queue is a secondary strip
    fileprivate var QueueSection: some View {
        VStack(spacing: dimensions.spacing.space8) {
            Summary

            if expanded {
                ForEach(downloads.order) { download in
                    Row(download)
                }
            }

            ExpandToggle
        }
    }

    fileprivate var ExpandToggle: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .contentTransition(.symbolEffect(.replace))

            Text(expanded ? "Hide" : "Show ^[\(downloads.order.count) Chapter](inflect: true)")
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

        return VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
            Text("\(completed) of \(total)")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(completed)))
                .animation(.snappy(duration: Layout.tick), value: completed)

            ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                .tint(.brand)
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

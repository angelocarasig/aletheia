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

    private enum Layout {
        static let fillOpacity = 0.05
        static let tick: TimeInterval = 0.2
    }

    var body: some View {
        Group {
            if downloads.order.isEmpty {
                ContentUnavailableView(
                    "Queue Is Empty",
                    systemImage: "arrow.down.circle",
                    description: Text(
                        "Chapters you download will appear here while they're being saved.")
                )
            } else {
                ScrollView {
                    VStack(spacing: dimensions.spacing.space8) {
                        Summary

                        ForEach(downloads.order) { download in
                            Row(download)
                        }
                    }
                    .padding(.horizontal, dimensions.spacing.space16)
                    .padding(.bottom, dimensions.spacing.space24)
                }
            }
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
